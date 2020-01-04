{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
module Language.Quartz.Eval where

import Control.Monad.State
import Control.Error
import qualified Data.Map as M
import Data.Dynamic
import Data.Foldable
import Data.IORef
import Language.Quartz.AST
import Language.Quartz.Lexer (AlexPosn)
import Language.Quartz.TypeCheck (fresh, argumentOf)
import qualified Language.Quartz.Std as Std
import qualified Data.PathTree as PathTree
import qualified Data.Primitive.Array as Array

data Context m = Context {
  decls :: PathTree.PathTree String (Decl AlexPosn),
  exprs :: M.Map Id (Expr AlexPosn),
  ffi :: M.Map Id ([Dynamic] -> ExceptT Std.FFIExceptions m (Expr AlexPosn)),
  impls :: M.Map (String, String) (Expr AlexPosn)
}

subst :: Expr AlexPosn -> String -> Expr AlexPosn -> Expr AlexPosn
subst expr var term = case expr of
  Var _ y | y == Id [var] -> term
  Var _ _                 -> expr
  Lit _                   -> expr
  FnCall f xs             -> FnCall f (map (\x -> subst x var term) xs)
  Let    x t              -> Let x (subst t var term)
  -- FIXME: shadowingしてる場合
  ClosureE (Closure argtypes expr) ->
    ClosureE (Closure argtypes (subst expr var term))
  OpenE _ -> expr
  Match e args ->
    Match (subst e var term) (map (\(pat, br) -> (pat, subst br var term)) args)
  If args ->
    If (map (\(pat, br) -> (subst pat var term, subst br var term)) args)
  Procedure es     -> Procedure $ map (\x -> subst x var term) es
  Unit             -> expr
  FFI p es         -> FFI p $ map (\x -> subst x var term) es
  Array    _       -> expr
  ArrayLit xs      -> ArrayLit (map (\x -> subst x var term) xs)
  IndexArray e1 e2 -> IndexArray (subst e1 var term) (subst e2 var term)
  ForIn v e es -> ForIn v (subst e var term) (map (\x -> subst x var term) es)
  Op    op e1 e2   -> Op op (subst e1 var term) (subst e2 var term)
  Member   e1  s   -> Member (subst e1 var term) s
  RecordOf s   xs  -> RecordOf s (map (\(x, y) -> (x, subst y var term)) xs)
  EnumOf   con ts  -> EnumOf con (map (\x -> subst x var term) ts)
  Assign   e1  e2  -> Assign (subst e1 var term) (subst e2 var term)
  Self _           -> expr
  MethodOf t s e   -> MethodOf t s (subst e var term)
  Any   _          -> expr
  Stmt  s          -> Stmt $ subst s var term
  Ref   v          -> Ref $ subst v var term
  Deref e          -> Deref $ subst e var term

isNormalForm :: Expr AlexPosn -> Bool
isNormalForm vm = case vm of
  Lit      _    -> True
  ClosureE _    -> True
  OpenE    _    -> True
  Unit          -> True
  Array _       -> True
  RecordOf _ fs -> all isNormalForm $ map snd fs
  EnumOf   _ _  -> True
  Any _         -> True
  Ref _         -> True
  _             -> False


match
  :: MonadIO m
  => Pattern
  -> Expr AlexPosn
  -> StateT (Context m) (ExceptT RuntimeExceptions m) ()
match pat term = case (pat, term) of
  (PVar (Id [v]), t) ->
    modify $ \ctx -> ctx { exprs = M.insert (Id [v]) t (exprs ctx) }
  (PLit lit, Lit lit') ->
    lift $ assertMay (lit == lit') ?? PatternNotMatch (PLit lit) term
  (PApp pf pxs, FnCall f xs) ->
    match pf f >> mapM_ (uncurry match) (zip pxs xs)
  (PVar u   , Var _ v    ) | u == v -> return ()
  (PVar u   , EnumOf v []) | u == v -> return ()
  (PApp p qs, EnumOf e fs) -> match p (Var Nothing e) >> zipWithM_ match qs fs
  (PAny     , _          ) -> return ()
  _ -> lift $ throwE $ PatternNotMatch pat term

data RuntimeExceptions
  = NotFound (Maybe AlexPosn) Id
  | PatternNotMatch Pattern (Expr AlexPosn)
  | PatternExhausted
  | FFIExceptions Std.FFIExceptions
  | Unreachable (Expr AlexPosn)
  | NumberOfArgumentsDoesNotMatch (Expr AlexPosn)
  deriving Show

-- Assume renaming is done
evalE
  :: MonadIO m
  => Expr AlexPosn
  -> StateT (Context m) (ExceptT RuntimeExceptions m) (Expr AlexPosn)
evalE vm = case vm of
  _ | isNormalForm vm -> return vm
  Var posn t          -> do
    ctx <- get
    case t of
      _ | t `M.member` exprs ctx -> do
        return $ exprs ctx M.! t

      Id [typ, name] | (name, typ) `M.member` impls ctx -> do
        return $ impls ctx M.! (name, typ)

      _ -> lift $ throwE $ NotFound posn t

  -- tricky part!
  -- トレイとのメソッド呼び出しx.f(y)はT::f(x,y)と解釈し直すが、このsyntaxはFnCallが外側に来てしまっているので
  -- 1段ネストの深いパターンマッチが必要
  FnCall (MethodOf typ name e1) es -> do
    ctx  <- get
    expr <- lift $ impls ctx M.!? (name, nameOfType typ) ?? NotFound
      Nothing
      (Id [name])
    evalE $ FnCall expr (e1 : es)

  FnCall f xs -> do
    f'  <- evalE f
    xs' <- mapM evalE xs
    case f' of
      ClosureE (Closure (FuncType tyvars fargs ret) fbody)
        | length (listArgTypes fargs) == length xs -> do
          let fbody' =
                foldl' (uncurry . subst) fbody $ zip (listArgNames fargs) xs'
          evalE fbody'
      _ -> lift $ throwE $ NumberOfArgumentsDoesNotMatch vm
  Let x t -> do
    f <- evalE t
    modify $ \ctx -> ctx { exprs = M.insert x f (exprs ctx) }
    return Unit
  Match t brs -> do
    t' <- evalE t
    fix
      ( \cont brs -> case brs of
        []            -> lift $ throwE PatternExhausted
        ((pat, b):bs) -> do
          ctx0   <- get
          result <- lift $ lift $ runExceptT $ execStateT (match pat t') ctx0
          case result of
            Left  _    -> cont bs
            Right ctx' -> put ctx' >> evalE b
      )
      brs
  Procedure es -> foldl' (\m e -> m >> evalE e) (return Unit) es
  FFI p es     -> get >>= \ctx -> do
    pf <- lift $ ffi ctx M.!? p ?? NotFound Nothing p
    lift $ withExceptT FFIExceptions $ pf $ map toDyn es
  ArrayLit es -> do
    es' <- mapM evalE es
    let arr = Array.fromList es'
    marr <- liftIO $ Array.thawArray arr 0 (Array.sizeofArray arr)
    return $ Array $ MArray marr
  IndexArray e1 e2 -> do
    arr <- evalE e1
    i   <- evalE e2
    case (arr, i) of
      (Array m, Lit (IntLit i)) -> liftIO $ Array.readArray (getMArray m) i
      _                         -> lift $ throwE $ Unreachable vm
  ForIn var e1 es -> do
    arr <- evalE e1
    ctx <- get
    case arr of
      (Array m) ->
        forM_ [0 .. Array.sizeofMutableArray (getMArray m) - 1] $ \i -> do
          r <- liftIO $ Array.readArray (getMArray m) i
          modify $ \ctx -> ctx { exprs = M.insert (Id [var]) r (exprs ctx) }
          mapM_ evalE es
      _ -> lift $ throwE $ Unreachable vm
    put ctx

    return Unit
  If brs -> fix
    ( \cont brs -> case brs of
      []                  -> return Unit
      ((cond, br):others) -> do
        result <- evalE cond
        case result of
          Lit (BoolLit True ) -> evalE br
          Lit (BoolLit False) -> cont others
          _                   -> error $ show result
    )
    brs
  Op op e1 e2 -> do
    r1 <- evalE e1
    r2 <- evalE e2
    case (op, r1, r2) of
      (Eq, _, _) ->
        return $ if r1 == r2 then Lit (BoolLit True) else Lit (BoolLit False)
      (Leq, Lit (IntLit x), Lit (IntLit y)) ->
        return $ if x <= y then Lit (BoolLit True) else Lit (BoolLit False)
  Member e1 v1 -> do
    r1 <- evalE e1
    case r1 of
      RecordOf _ fields -> do
        return $ (\(Just x) -> x) $ lookup v1 fields
      _ -> lift $ throwE $ Unreachable vm
  Stmt e           -> evalE e
  RecordOf name fs -> fmap (RecordOf name) $ forM fs $ \(x, y) -> do
    y' <- evalE y
    return (x, y')
  Assign e1 e2 -> do
    ctx <- get
    case e1 of
      Ref (Var Nothing v) -> do
        r2 <- evalE e2
        modify $ \ctx -> ctx { exprs = M.insert v r2 $ exprs ctx }
      -- 多段にネストされたメンバーへの代入が出来ないが今は適当
      Ref (Member (Var _ r) v) -> do
        r2 <- evalE e2
        modify $ \ctx -> ctx
          { exprs = M.adjust
              ( \(RecordOf f rc) -> RecordOf f
                $ map (\(x, y) -> if x == v then (x, r2) else (x, y)) rc
              )
              r
            $ exprs ctx
          }
      IndexArray arr i -> do
        arr' <- evalE arr
        i'   <- evalE i
        r2   <- evalE e2

        case (arr', i') of
          (Array marr, Lit (IntLit n)) -> do
            liftIO $ Array.writeArray (getMArray marr) n r2
          _ -> lift $ throwE $ Unreachable vm
      _ -> lift $ throwE $ Unreachable vm
      {-
      ArrayIndexAssign arr i -> do
        arr' <- evalE arr
        i'   <- evalE i
        r2   <- evalE e2
        case (arr', i', r2) of
          (Array marr, Lit (IntLit n), val) -> do
            liftIO $ Array.writeArray (getMArray marr) n val
            return Unit
          _ -> lift $ throwE $ Unreachable vm
      RecordFieldAssign rc f -> do
        rc' <- evalE rc
        r2  <- evalE e2
        case (rc', r2) of
          (RecordOf name rc, val) -> do
            return $ RecordOf name $ map
              (\(x, y) -> if x == f then (x, r2) else (x, y))
              rc
          _ -> lift $ throwE $ Unreachable vm
      _ -> lift $ throwE $ Unreachable vm
      -}

    return Unit
  _ -> lift $ throwE $ Unreachable vm

runEvalE
  :: MonadIO m => Expr AlexPosn -> ExceptT RuntimeExceptions m (Expr AlexPosn)
runEvalE m = evalStateT (evalE m) (std M.empty)

evalD
  :: MonadIO m
  => Decl AlexPosn
  -> StateT (Context m) (ExceptT RuntimeExceptions m) ()
evalD decl = go [] decl
 where
  go path decl = case decl of
    Enum name _ fs -> do
      forM_ fs $ \(EnumField f typs) -> do
        bs <- mapM (\_ -> fresh) typs
        let vars = map (Var Nothing . Id . return) bs
        modify $ \ctx -> ctx
          { exprs = M.insert
              (Id [name, f])
              ( if null typs
                then EnumOf (Id [name, f]) []
                else ClosureE
                  ( Closure
                    (FuncType [] (ArgType False False $ zip bs typs) NoType)
                    (EnumOf (Id [name, f]) vars)
                  )
              )
            $ exprs ctx
          }

    Record d _ _ ->
      modify $ \ctx -> ctx { decls = PathTree.insert [d] decl (decls ctx) }
    Func d body ->
      modify $ \ctx ->
        ctx { exprs = M.insert (Id [d]) (ClosureE body) (exprs ctx) }
    ExternalFunc name (FuncType tyvars args ret) -> do
      bs <- mapM (\_ -> fresh) $ (\(ArgType _ _ xs) -> xs) args
      let args' = zip bs $ listArgTypes args

      evalD $ Func
        name
        ( Closure
          (FuncType tyvars (ArgType False False args') ret)
          (FFI (Id [name]) (map (\n -> Var Nothing (Id [n])) $ map fst args'))
        )
    Interface _ _ _             -> return ()
    Derive name _ (Just typ) ds -> modify $ \ctx -> ctx
      { impls = M.union
        ( M.fromList
        $ map (\(Func fn body) -> ((fn, nameOfType typ), ClosureE body)) ds
        )
        (impls ctx)
      }
    Derive name vars Nothing ds -> modify $ \ctx -> ctx
      { impls = M.union
        (M.fromList $ map (\(Func fn body) -> ((fn, name), ClosureE body)) ds)
        (impls ctx)
      }

std
  :: MonadIO m
  => M.Map Id ([Dynamic] -> ExceptT Std.FFIExceptions m (Expr AlexPosn))
  -> Context m
std exts = Context
  { ffi   = M.union Std.ffi exts
  , exprs = M.empty
  , decls = PathTree.empty
  , impls = M.empty
  }

runMain
  :: MonadIO m => [Decl AlexPosn] -> ExceptT RuntimeExceptions m (Expr AlexPosn)
runMain = runMainWith M.empty

runMainWith
  :: MonadIO m
  => M.Map Id ([Dynamic] -> ExceptT Std.FFIExceptions m (Expr AlexPosn))
  -> [Decl AlexPosn]
  -> ExceptT RuntimeExceptions m (Expr AlexPosn)
runMainWith lib decls = flip evalStateT (std lib) $ do
  mapM_ evalD decls
  evalE (FnCall (Var Nothing (Id ["main"])) [])
