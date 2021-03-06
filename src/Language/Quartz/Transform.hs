module Language.Quartz.Transform where

import           Language.Quartz.AST

varToConType :: [String] -> Type -> Type
varToConType vars t = case t of
  ConType (Id [i]) | i `elem` vars -> VarType i
  FnType xs y -> FnType (map (varToConType vars) xs) (varToConType vars y)
  AppType x ys -> AppType (varToConType vars x) (map (varToConType vars) ys)
  RefType x -> RefType (varToConType vars x)
  _ -> t

varToConTypeArgTypes :: [String] -> FuncType -> FuncType
varToConTypeArgTypes vars' (FuncType vars (ArgType ref self args) ret) =
  FuncType
    vars
    ( ArgType ref self
    $ map (\(x, y) -> (x, varToConType (vars' ++ vars) y)) args
    )
    (varToConType (vars' ++ vars) ret)

transformVarConTypeE :: Expr posn -> Expr posn
transformVarConTypeE expr = go [] expr
 where
  go vars' expr = case unwrapExpr expr of
    Var _                     -> expr
    Lit _                     -> expr
    FnCall x ys -> srcSpanExpr' expr $ FnCall (go vars' x) (map (go vars') ys)
    Let    x e                -> srcSpanExpr' expr $ Let x (go vars' e)
    ClosureE (Closure args e) -> srcSpanExpr' expr
      $ ClosureE (Closure (varToConTypeArgTypes vars' args) (go vars' e))
    Match e bs -> srcSpanExpr' expr
      $ Match (go vars' e) (map (\(p, e) -> (p, go vars' e)) bs)
    If es ->
      srcSpanExpr' expr $ If (map (\(x, y) -> (go vars' x, go vars' y)) es)
    Procedure es -> srcSpanExpr' expr $ Procedure (map (go vars') es)
    Unit         -> srcSpanExpr' expr $ Unit
    FFI x es     -> srcSpanExpr' expr $ FFI x (map (go vars') es)
    Array    _   -> expr
    ArrayLit es  -> srcSpanExpr' expr $ ArrayLit (map (go vars') es)
    IndexArray e1 e2 ->
      srcSpanExpr' expr $ IndexArray (go vars' e1) (go vars' e2)
    ForIn s e es ->
      srcSpanExpr' expr $ ForIn s (go vars' e) (map (go vars') es)
    Op op e1 e2 -> srcSpanExpr' expr $ Op op (go vars' e1) (go vars' e2)
    Member e r  -> srcSpanExpr' expr $ Member (go vars' e) r
    RecordOf s es ->
      srcSpanExpr' expr $ RecordOf s (map (\(x, y) -> (x, go vars' y)) es)
    EnumOf s  es -> srcSpanExpr' expr $ EnumOf s (map (go vars') es)
    Assign e1 e2 -> srcSpanExpr' expr $ Assign (go vars' e1) (go vars' e2)
    Self s       -> srcSpanExpr' expr $ Self s
    Stmt s       -> srcSpanExpr' expr $ Stmt $ go vars' s
    LetRef x e   -> srcSpanExpr' expr $ LetRef x (go vars' e)
    Deref e      -> srcSpanExpr' expr $ Deref $ go vars' e

transformVarConTypeD :: Decl posn -> Decl posn
transformVarConTypeD decl = go [] decl
 where
  go vars' decl = case decl of
    Enum name vars efs ->
      Enum name vars (map (goEnumField (vars' ++ vars)) efs)
    Record name vars rfs ->
      Record name vars (map (goRecordField (vars' ++ vars)) rfs)
    OpenD s                       -> OpenD s
    Func name (Closure args expr) -> Func
      name
      (Closure (varToConTypeArgTypes vars' args) (transformVarConTypeE expr))
    ExternalFunc name args ->
      ExternalFunc name (varToConTypeArgTypes vars' args)
    Interface name vars fs ->
      Interface name vars (map (goFnType (vars' ++ vars)) fs)
    Derive name vars implFor ds ->
      Derive name vars implFor $ map (go (vars' ++ vars)) ds

  goEnumField vars (EnumField s ts) = EnumField s (map (varToConType vars) ts)
  goRecordField vars (RecordField s t) = RecordField s (varToConType vars t)
  goFnType vars' (name, args) = (name, varToConTypeArgTypes vars' args)

transformSelfTypeE :: Type -> Expr posn -> Expr posn
transformSelfTypeE typ expr = go expr
 where
  apply t typ = case typ of
    SelfType         -> t
    FnType  args ret -> FnType (map (apply t) args) (apply t ret)
    AppType t1   ts  -> AppType (apply t t1) (map (apply t) ts)
    RefType typ'     -> RefType $ apply t typ'
    _                -> typ

  go expr = case unwrapExpr expr of
    Var _       -> expr
    Lit _       -> expr
    FnCall x ys -> srcSpanExpr' expr $ FnCall (go x) (map go ys)
    Let    x e  -> srcSpanExpr' expr $ Let x (go e)
    ClosureE (Closure args e) ->
      srcSpanExpr' expr $ ClosureE (Closure (goArgTypes args) (go e))
    Match e bs ->
      srcSpanExpr' expr $ Match (go e) (map (\(p, e) -> (p, go e)) bs)
    If es -> srcSpanExpr' expr $ If (map (\(x, y) -> (go x, go y)) es)
    Procedure es     -> srcSpanExpr' expr $ Procedure (map go es)
    Unit             -> srcSpanExpr' expr $ Unit
    FFI x es         -> srcSpanExpr' expr $ FFI x (map go es)
    Array    _       -> expr
    ArrayLit es      -> srcSpanExpr' expr $ ArrayLit (map go es)
    IndexArray e1 e2 -> srcSpanExpr' expr $ IndexArray (go e1) (go e2)
    ForIn s  e  es   -> srcSpanExpr' expr $ ForIn s (go e) (map go es)
    Op    op e1 e2   -> srcSpanExpr' expr $ Op op (go e1) (go e2)
    Member e r       -> srcSpanExpr' expr $ Member (go e) r
    RecordOf s es ->
      srcSpanExpr' expr $ RecordOf s (map (\(x, y) -> (x, go y)) es)
    EnumOf s  es  -> srcSpanExpr' expr $ EnumOf s (map go es)
    Assign e1 e2  -> srcSpanExpr' expr $ Assign (go e1) (go e2)
    Self selfType -> srcSpanExpr' expr $ Self (apply typ selfType)
    Stmt e        -> srcSpanExpr' expr $ Stmt $ go e
    LetRef x e    -> srcSpanExpr' expr $ LetRef x (go e)
    Deref e       -> srcSpanExpr' expr $ Deref $ go e

  goArgTypes (FuncType vars (ArgType ref self args) ret) = FuncType
    vars
    (ArgType ref self $ map (\(x, y) -> (x, apply typ y)) args)
    (apply typ ret)

-- derive (X for) T {}のとき、スコープ内のselfをTに置換する
-- 関数宣言時の&selfについては、Tを&Tと解釈する
transformSelfTypeD :: Decl posn -> Decl posn
transformSelfTypeD decl = case decl of
  Derive name vars (Just t) decls ->
    Derive name vars (Just t) $ map (go t) decls
  Derive name vars Nothing decls ->
    Derive name vars Nothing $ map (go (createType name vars)) decls
  _ -> decl
 where
  createType name vars = mayAppType (ConType (Id [name])) (map VarType vars)

  apply t typ = case typ of
    SelfType         -> t
    FnType  args ret -> FnType (map (apply t) args) (apply t ret)
    AppType t1   ts  -> AppType (apply t t1) (map (apply t) ts)
    RefType typ'     -> RefType $ apply t typ'
    _                -> typ

  goArgTypes t (FuncType vars (ArgType ref self args) ret) = FuncType
    vars
    (ArgType ref self $ map (\(x, y) -> (x, apply t y)) args)
    (apply t ret)

  go t (Func name (Closure argtypes@(FuncType _ at _) body)) = Func
    name
    (Closure
      (goArgTypes t argtypes)
      (transformSelfTypeE (if isRefSelfArgType at then RefType t else t) body)
    )

desugarOpE :: Expr posn -> Expr posn
desugarOpE expr = go expr
 where
  go expr = case unwrapExpr expr of
    Op op e1 e2 ->
      let e1' = go e1
          e2' = go e2
      in  srcSpanExpr' expr $ case op of
            Add  -> FnCall (srcSpanExpr' expr $ Member e1' "_add_") [e2']
            Sub  -> FnCall (srcSpanExpr' expr $ Member e1' "_subtract_") [e2']
            Mult -> FnCall (srcSpanExpr' expr $ Member e1' "_mult_") [e2']
            Div  -> FnCall (srcSpanExpr' expr $ Member e1' "_div_") [e2']
            Leq  -> FnCall (srcSpanExpr' expr $ Member e1' "_leq_") [e2']
            Lt   -> FnCall (srcSpanExpr' expr $ Member e1' "_lt_") [e2']
            Geq  -> FnCall (srcSpanExpr' expr $ Member e1' "_geq_") [e2']
            Gt   -> FnCall (srcSpanExpr' expr $ Member e1' "_gt_") [e2']
            _    -> Op op e1' e2'
    Var _       -> expr
    Lit _       -> expr
    FnCall x ys -> srcSpanExpr' expr $ FnCall (go x) (map go ys)
    Let    x e  -> srcSpanExpr' expr $ Let x (go e)
    ClosureE (Closure args e) ->
      srcSpanExpr' expr $ ClosureE (Closure args (go e))
    Match e bs ->
      srcSpanExpr' expr $ Match (go e) (map (\(p, e) -> (p, go e)) bs)
    If es -> srcSpanExpr' expr $ If (map (\(x, y) -> (go x, go y)) es)
    Procedure es     -> srcSpanExpr' expr $ Procedure (map go es)
    Unit             -> srcSpanExpr' expr $ Unit
    FFI x es         -> srcSpanExpr' expr $ FFI x (map go es)
    Array    _       -> expr
    ArrayLit es      -> srcSpanExpr' expr $ ArrayLit (map go es)
    IndexArray e1 e2 -> srcSpanExpr' expr $ IndexArray (go e1) (go e2)
    ForIn s e es     -> srcSpanExpr' expr $ ForIn s (go e) (map go es)
    Member e r       -> srcSpanExpr' expr $ Member (go e) r
    RecordOf s es ->
      srcSpanExpr' expr $ RecordOf s (map (\(x, y) -> (x, go y)) es)
    EnumOf s  es  -> srcSpanExpr' expr $ EnumOf s (map go es)
    Assign e1 e2  -> srcSpanExpr' expr $ Assign (go e1) (go e2)
    Self selfType -> srcSpanExpr' expr $ Self selfType
    Stmt e        -> srcSpanExpr' expr $ Stmt $ go e
    LetRef x e    -> srcSpanExpr' expr $ LetRef x (go e)
    Deref e       -> srcSpanExpr' expr $ Deref $ go e

desugarOpD :: Decl posn -> Decl posn
desugarOpD decl = go decl
 where
  go decl = case decl of
    Func name (Closure args expr) -> Func name (Closure args (desugarOpE expr))
    Derive name vars implFor ds -> Derive name vars implFor $ map desugarOpD ds
    _ -> decl

transformIgnorePosnE :: Expr posn -> Expr posn
transformIgnorePosnE expr = go expr
 where
  go expr = case unwrapExpr expr of
    Var v       -> srcSpanExpr' expr $ Var v
    Lit _       -> expr
    FnCall x ys -> srcSpanExpr' expr $ FnCall (go x) (map go ys)
    Let    x e  -> srcSpanExpr' expr $ Let x (go e)
    ClosureE (Closure args e) ->
      srcSpanExpr' expr $ ClosureE (Closure args (go e))
    Match e bs ->
      srcSpanExpr' expr $ Match (go e) (map (\(p, e) -> (p, go e)) bs)
    If es -> srcSpanExpr' expr $ If (map (\(x, y) -> (go x, go y)) es)
    Procedure es     -> srcSpanExpr' expr $ Procedure (map go es)
    Unit             -> srcSpanExpr' expr $ Unit
    FFI x es         -> srcSpanExpr' expr $ FFI x (map go es)
    Array    _       -> expr
    ArrayLit es      -> srcSpanExpr' expr $ ArrayLit (map go es)
    IndexArray e1 e2 -> srcSpanExpr' expr $ IndexArray (go e1) (go e2)
    ForIn s  e  es   -> srcSpanExpr' expr $ ForIn s (go e) (map go es)
    Op    op e1 e2   -> srcSpanExpr' expr $ Op op (go e1) (go e2)
    Member e r       -> srcSpanExpr' expr $ Member (go e) r
    RecordOf s es ->
      srcSpanExpr' expr $ RecordOf s (map (\(x, y) -> (x, go y)) es)
    EnumOf s  es  -> srcSpanExpr' expr $ EnumOf s (map go es)
    Assign e1 e2  -> srcSpanExpr' expr $ Assign (go e1) (go e2)
    Self selfType -> expr
    Stmt e        -> srcSpanExpr' expr $ Stmt $ go e
    LetRef x e    -> srcSpanExpr' expr $ LetRef x (go e)
    Deref e       -> srcSpanExpr' expr $ Deref $ go e

transformIgnorePosnD :: Decl posn -> Decl posn
transformIgnorePosnD decl = go decl
 where
  go decl = case decl of
    Func name (Closure args expr) ->
      Func name (Closure args (transformIgnorePosnE expr))
    Derive name vars implFor ds -> Derive name vars implFor $ map go ds
    _                           -> decl
