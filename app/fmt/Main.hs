{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FlexibleContexts #-}
module Main where

import Data.Text.Prettyprint.Doc
import Data.Text.Prettyprint.Doc.Util
import Data.Text.Prettyprint.Doc.Render.Text
import Data.List
import Language.Quartz
import System.Environment
import System.IO

listed :: [Doc ann] -> Doc ann
listed = align . sep . punctuate comma

block :: [Doc ann] -> Doc ann
block = enclose hardline hardline . indent 2 . align . vsep

generics :: [String] -> Doc ann
generics tyvars =
  if null tyvars then emptyDoc else angles $ listed $ map pretty tyvars

instance Pretty Id where
  pretty (Id vs) = foldl1 (\x y -> x <> pretty "::" <> y) $ map pretty vs

instance Pretty Op where
  pretty Eq = pretty "=="
  pretty Leq = pretty "<="
  pretty Add = pretty "+"
  pretty Sub = pretty "-"
  pretty Mult = pretty "*"
  pretty Div = pretty "/"

instance Pretty Literal where
  pretty lit = case lit of
    BoolLit True -> pretty "true"
    BoolLit False -> pretty "false"
    IntLit v -> pretty v
    DoubleLit v -> pretty v
    CharLit v -> pretty v
    StringLit v -> dquotes $ pretty v

instance Pretty Pattern where
  pretty pat = case pat of
    PVar v -> pretty v
    PLit lit -> pretty lit
    PApp p1 ps -> pretty p1 <> parens (listed $ map pretty ps)
    PAny -> pretty "_"

instance Pretty (Closure posn) where
  pretty (Closure typ body) = pretty typ <+> pretty "->" <+> pretty body

instance Pretty (Expr posn) where
  pretty expr = case expr of
    Var _ v -> pretty v
    Lit lit -> pretty lit
    FnCall e1 es -> pretty e1 <> parens (listed $ map pretty es)
    Let v e -> pretty "let" <+> pretty v <+> equals <+> pretty e
    ClosureE c -> pretty c
    Match e brs -> pretty "match" <+> pretty e <+> braces (block $ map (\(x,y) -> pretty x <+> pretty "=>" <+> pretty y <> comma) brs)
    If es -> pretty "if" <+> braces (block $ map (\(x,y) ->
      -- ifの条件部は演算子を含むときは括弧を付けたほうが見やすいため
      (case x of
        Op _ _ _ -> parens $ pretty x
        _ -> pretty x
        )
      <+> pretty "=>" <+> pretty y <> comma) es)
    Procedure es -> braces $ block $ map pretty es
    Unit -> parens emptyDoc
    ArrayLit es -> brackets (listed $ map pretty es)
    IndexArray e1 e2 -> pretty e1 <> brackets (pretty e2)
    ForIn v e1 es -> pretty "for" <+> pretty v <+> pretty "in" <+> pretty e1 <+> braces (block $ map pretty es)
    Op op e1 e2 -> pretty e1 <+> pretty op <+> pretty e2
    Member e1 v -> pretty e1 <> dot <> pretty v
    RecordOf s vs -> pretty s <+> braces (listed $ map (\(x,y) -> pretty x <> colon <+> pretty y) vs)
    EnumOf i xs -> pretty i <> parens (listed $ map pretty xs)
    Assign e1 e2 -> pretty e1 <+> equals <+> pretty e2
    Self typ -> pretty "self"
    Stmt s -> pretty s <> semi

instance Pretty Type where
  pretty typ = case typ of
    VarType s -> pretty s
    ConType (Id [s]) -> pretty s
    AppType con args -> pretty con <> angles (listed $ map pretty args)
    FnType args ret -> pretty "func" <> parens (listed $ map pretty args)
    SelfType -> pretty "self"

instance Pretty ArgType where
  pretty (ArgType self args) = parens (listed $ (if self then (pretty "self" :) else id) $ map (\(x,y) -> pretty x <> colon <+> pretty y) args)

instance Pretty FuncType where
  pretty (FuncType tyvars args ret) = align $
    generics tyvars
    <> pretty args
    -- super ugly!
    <> (if ret == ConType (Id ["unit"]) then emptyDoc else colon <+> pretty ret)

instance Pretty EnumField where
  pretty (EnumField name typs) =
    pretty name
    <> if null typs then emptyDoc else parens (listed $ map pretty typs)

instance Pretty RecordField where
  pretty (RecordField s t) = pretty s <> colon <+> pretty t

instance Pretty (Decl posn) where
  pretty decl = case decl of
    Enum name tyvars fields -> align $
      pretty "enum"
      <+> pretty name
      <> generics tyvars
      <+> braces (block $ map (\d -> pretty d <> comma) fields)
    Record name tyvars fields -> align $
      pretty "record"
      <+> pretty name
      <> generics tyvars
      <+> braces (block $ map (\d -> pretty d <> comma) fields)
    Func name (Closure argtypes body) -> align $
      pretty "func"
      <+> pretty name
      <> pretty argtypes
      <+> pretty body
    ExternalFunc name argtypes -> align $
      pretty "external"
      <+> pretty "func"
      <+> pretty name
      <> pretty argtypes
      <> semi
    Interface name tyvars fs -> align $
      pretty "interface"
      <+> pretty name
      <> generics tyvars
      <+> braces (block $ map (\(name, ft) -> pretty "func" <+> pretty name <> pretty ft <> semi) fs)
    Derive name tyvars for ds -> align $
      pretty "derive"
      <+> pretty name
      <> generics tyvars
      <+> maybe emptyDoc (\typ -> pretty "for" <+> pretty typ) for
      <+> braces (block $ punctuate hardline $ map (\d -> pretty d) ds)

instance {-# OVERLAPS #-} Pretty (Decl posn) => Pretty [Decl posn] where
  pretty ds = vsep $ map (\d -> pretty d <> hardline) ds

main = do
  args <- getArgs
  body <- case args of
    [] -> getContents
    _  -> do
      let filepath = head args
      readFile filepath

  case parseModule body of
    Left  err   -> print err
    Right decls -> do
      let p = pretty decls
      putDocW 80 p
      -- VSCode側でやるので一旦消去
      --withFile filepath WriteMode
      --  $ \handle -> renderIO handle $ layoutSmart defaultLayoutOptions p
