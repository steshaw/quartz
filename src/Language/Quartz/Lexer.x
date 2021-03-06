{
module Language.Quartz.Lexer where

import Data.Default
}

%wrapper "posn"

$digit = [0-9]
$alpha = [a-zA-Z]
@string = \" ($printable # \")* \"

tokens :-
  $white+ ;
  "//".*  ;
  func { wrap (\_ -> TFunc) }
  enum { wrap (\_ -> TEnum) }
  record { wrap $ \_ -> TRecord }
  open { wrap $ \_ -> TOpen }
  let { wrap $ \_ -> TLet }
  self { wrap $ \_ -> TSelf }
  match { wrap $ \_ -> TMatch }
  external { wrap $ \_ -> TExternal }
  for { wrap $ \_ -> TFor }
  in { wrap $ \_ -> TIn }
  if { wrap $ \_ -> TIf }
  else { wrap $ \_ -> TElse }
  interface { wrap $ \_ -> TInterface }
  derive { wrap $ \_ -> TDerive }
  ref { wrap $ \_ -> TRef }

  -- 避けられるなら予約語から外したい
  true { wrap $ \_ -> TTrue }
  false { wrap $ \_ -> TFalse }

  \< { wrap $ \_ -> TLAngle }
  \> { wrap $ \_ -> TRAngle }
  \( { wrap $ \_ -> TLParen }
  \) { wrap $ \_ -> TRParen }
  \{ { wrap $ \_ -> TLBrace }
  \} { wrap $ \_ -> TRBrace }
  \[ { wrap $ \_ -> TLBracket }
  \] { wrap $ \_ -> TRBracket }
  \, { wrap $ \_ -> TComma }
  \: { wrap $ \_ -> TColon }
  \:: { wrap $ \_ -> TColon2 }
  \; { wrap $ \_ -> TSemiColon }
  \. { wrap $ \_ -> TDot }
  \-> { wrap $ \_ -> TArrow }
  \=> { wrap $ \_ -> TDArrow }
  \= { wrap $ \_ -> TEq }
  \== { wrap $ \_ -> TEq2 }
  \_ { wrap $ \_ -> TUnderscore }
  \+ { wrap $ \_ -> TPlus }
  \- { wrap $ \_ -> TMinus }
  \* { wrap $ \_ -> TStar }
  \/ { wrap $ \_ -> TSlash }
  \<= { wrap $ \_ -> TLeq }
  \>= { wrap $ \_ -> TGeq }
  array! { wrap $ \_ -> TArrayLit }
  $digit+ { wrap (TInt . read) }
  [$alpha \_] [$alpha $digit \_]* { wrap TVar }
  @string { wrap (\s -> TStrLit $ init $ tail s) }

{
data Token
  = TFunc
  | TEnum
  | TRecord
  | TOpen
  | TLet
  | TSelf
  | TMatch
  | TExternal
  | TFor
  | TIn
  | TIf
  | TElse
  | TRef
  | TTrue
  | TFalse
  | TInterface
  | TDerive
  | TLAngle
  | TRAngle
  | TLParen
  | TRParen
  | TLBrace
  | TRBrace
  | TLBracket
  | TRBracket
  | TComma
  | TColon
  | TColon2
  | TSemiColon
  | TDot
  | TArrow
  | TDArrow
  | TEq
  | TEq2
  | TUnderscore
  | TPlus
  | TMinus
  | TStar
  | TSlash
  | TLeq
  | TArrayLit
  | TGeq
  | TInt Int
  | TVar String
  | TStrLit String
  deriving (Eq, Show)

data Lexeme = Lexeme AlexPosn Token
  deriving (Eq, Show)

posOfLexeme :: Lexeme -> AlexPosn
posOfLexeme (Lexeme p _) = p

tokenOfLexeme :: Lexeme -> Token
tokenOfLexeme (Lexeme _ t) = t

wrap :: (String -> Token) -> AlexPosn -> String -> Lexeme
wrap f p s = Lexeme p (f s)

instance Default AlexPosn where
  def = AlexPn 0 0 0
}
