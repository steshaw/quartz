module Language.Quartz.AST where

import Data.Primitive.Array
import Control.Monad.Primitive (RealWorld)

data Literal
  = IntLit Int
  | DoubleLit Double
  | CharLit Char
  | StringLit String
  | BoolLit Bool
  deriving (Eq, Show)

data Id = Id [String]
  deriving (Eq, Ord, Show)

data Op
  = Eq
  deriving (Eq, Show)

data Expr
  = Var Id
  | Lit Literal
  | FnCall Expr [Expr]
  | Let Id Expr
  | ClosureE Closure
  | OpenE Id
  | Match Expr [(Pattern, Expr)]
  | If [(Expr, Expr)]
  | Procedure [Expr]
  | Unit
  | NoExpr
  | FFI Id [Expr]
  -- primitiveのときはMutableByteArrayにしたい
  | Array MArray
  | ArrayLit [Expr]
  | IndexArray Expr Expr
  | ForIn String Expr [Expr]
  | Op Op Expr Expr
  | Member Expr String
  | RecordOf String [(String, Expr)]
  deriving (Eq, Show)

newtype MArray = MArray { getMArray :: MutableArray RealWorld Expr }
  deriving Eq

instance Show MArray where
  show _ = "<<array>>"

data Type
  = ArrowType Type Type
  | ConType Id
  | VarType String
  | AppType Type [Type]
  | SelfType
  | NoType
  deriving (Eq, Show)

data Scheme = Scheme [String] Type
  deriving (Eq, Show)

data Pattern
  = PVar String
  | PLit Literal
  | PApp Pattern [Pattern]
  | PAny
  deriving (Eq, Show)

data ArgTypes = ArgTypes [String] [(String, Type)] Type
  deriving (Eq, Show)

data Closure = Closure ArgTypes Expr
  deriving (Eq, Show)

data Decl
  = Enum String [EnumField]
  | Record String [RecordField]
  | Instance Type [Decl]
  | OpenD Id
  | Func String Closure
  | Method String Closure
  | ExternalFunc String ArgTypes
  deriving (Eq, Show)

data EnumField = EnumField String [Type]
  deriving (Eq, Show)

data RecordField = RecordField String Type
  deriving (Eq, Show)
