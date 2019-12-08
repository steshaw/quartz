{
module Language.Quartz.Lexer where
}

%wrapper "posn"

$digit = [0-9]
$alpha = [a-zA-Z]
@string = \" ($printable # \")* \"

tokens :-
  $white+ ;
  func { wrap (\_ -> TFunc) }
  enum { wrap (\_ -> TEnum) }
  record { wrap $ \_ -> TRecord }
  instance { wrap $ \_ -> TInstance }
  open { wrap $ \_ -> TOpen }
  let { wrap $ \_ -> TLet }
  self { wrap $ \_ -> TSelf }
  match { wrap $ \_ -> TMatch }
  external { wrap $ \_ -> TExternal }
  for { wrap $ \_ -> TFor }
  in { wrap $ \_ -> TIn }
  if { wrap $ \_ -> TIf }
  else { wrap $ \_ -> TElse }

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
  \* { wrap $ \_ -> TStar }
  \= { wrap $ \_ -> TEq }
  \== { wrap $ \_ -> TEq2 }
  \_ { wrap $ \_ -> TUnderscore }
  $digit+ { wrap (TInt . read) }
  [$alpha \_] [$alpha $digit \_]* { wrap TVar }
  @string { wrap TStrLit }

{
data Token
  = TFunc
  | TEnum
  | TRecord
  | TInstance
  | TOpen
  | TLet
  | TSelf
  | TMatch
  | TExternal
  | TFor
  | TIn
  | TIf
  | TElse
  | TTrue
  | TFalse
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
  | TStar
  | TEq
  | TEq2
  | TUnderscore
  | TInt Int
  | TVar String
  | TStrLit String
  deriving (Eq, Show)

data Lexeme = Lexeme AlexPosn Token
  deriving (Eq, Show)

wrap :: (String -> Token) -> AlexPosn -> String -> Lexeme
wrap f p s = Lexeme p (f s)
}
