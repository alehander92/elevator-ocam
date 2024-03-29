(*
  Elevator:
  
  Program ::= Stmts
  Stmts ::= Stmt | Stmt '\n' Stmts
  Stmt ::= Assign | Receive | Send
  Assign ::= 'let' Name '=' Exp
  Receive ::= '->' Name ':' nl PatternExpr*
  Send ::= Name '<-' Exp

  Exp ::= Call | NewInstance | Lambda | Int | String | Name | BinOp
  Call ::= Name '(' (Exp ws?)* ')'
  NewInstance ::= Typename '(' (Exp ws?)* ')'
  Lambda ::= '[' ParameterList? '~' Stmts ']'
  ParameterList ::= '(' (Name ws)* ')'
  Int ::= ([0-9])+
  String ::= '"' ([^\"]*) '"'
  Name ::= [A-Za-z][a-zA-Z0-9_]*
  BinOp ::= Exp Op Exp

  PatternExpr ::= '|' ws Pattern ws '~' ws Exp
  Pattern ::= TypePattern | Int
  TypePattern ::= Typename ws (Name ws?)*
  Typename := [A-Z][a-zA-Z]*
*)

(* ----------------------------- opal.ml START ------------------------------ *)
module LazyStream = struct
  type 'a t = Cons of 'a * 'a t Lazy.t | Nil
  let of_stream stream =
    let rec next stream =
      try Cons(Stream.next stream, lazy (next stream))
      with Stream.Failure -> Nil
    in
    next stream
  let of_string str = str |> Stream.of_string |> of_stream
  let of_channel ic = ic |> Stream.of_channel |> of_stream
  let of_function f =
    let rec next f =
      match f () with
      | Some x -> Cons(x, lazy (next f))
      | None -> Nil
    in
    next f
end
let implode l = String.concat "" (List.map (String.make 1) l)
let explode s =
  let l = ref [] in
  String.iter (fun c -> l := c :: !l) s;
  List.rev !l
let (%) f g = fun x -> g (f x)
type 'token input = 'token LazyStream.t
type ('token, 'result) parser = 'token input -> ('result * 'token input) option
let parse parser input =
  match parser input with
  | Some(res, _) -> Some res
  | None -> None
let return x input = Some(x, input)
let (>>=) x f =
  fun input ->
    match x input with
    | Some(result', input') -> f result' input'
    | None -> None
let (<|>) x y =
  fun input ->
    match x input with
    | Some _ as ret -> ret
    | None -> y input
let rec scan x input =
  match x input with
  | Some(result', input') -> LazyStream.Cons(result', lazy (scan x input'))
  | None -> LazyStream.Nil
let mzero _ = None
let any = function
  | LazyStream.Cons(token, input') -> Some(token, Lazy.force input')
  | LazyStream.Nil -> None
let satisfy test = any >>= (fun res -> if test res then return res else mzero)
let eof x = function LazyStream.Nil -> Some(x, LazyStream.Nil) | _ -> None
let (=>) x f = x >>= fun r -> return (f r)
let (>>) x y = x >>= fun _ -> y
let (<<) x y = x >>= fun r -> y >>= fun _ -> return r
let (<~>) x xs = x >>= fun r -> xs >>= fun rs -> return (r :: rs)
let rec choice = function [] -> mzero | h :: t -> (h <|> choice t)
let rec count n x = if n > 0 then x <~> count (n - 1) x else return []
let between op ed x = op >> x << ed
let option default x = x <|> return default
let optional x = option () (x >> return ())
let rec skip_many x = option () (x >>= fun _ -> skip_many x)
let skip_many1 x = x >> skip_many x
let rec many x = option [] (x >>= fun r -> many x >>= fun rs -> return (r :: rs))
let many1 x = x <~> many x
let sep_by1 x sep = x <~> many (sep >> x)
let sep_by x sep = sep_by1 x sep <|> return []
let end_by1 x sep = sep_by1 x sep << sep
let end_by x sep = end_by1 x sep <|> return []
let chainl1 x op =
  let rec loop a = (op >>= fun f -> x >>= fun b -> loop (f a b)) <|> return a in
  x >>= loop
let chainl x op default = chainl1 x op <|> return default
let rec chainr1 x op =
  x >>= fun a -> (op >>= fun f -> chainr1 x op >>= f a) <|> return a
let chainr x op default = chainr1 x op <|> return default
let exactly x = satisfy ((=) x)
let one_of  l = satisfy (fun x -> List.mem x l)
let none_of l = satisfy (fun x -> not (List.mem l x))
let range l r = satisfy (fun x -> l <= x && x <= r)
let space     = one_of [' '; '\t'; '\r'; '\n']
let spaces    = skip_many space
let newline   = exactly '\n'
let tab       = exactly '\t'
let upper     = range 'A' 'Z'
let lower     = range 'a' 'z'
let digit     = range '0' '9'
let letter    = lower  <|> upper
let alpha_num = letter <|> digit
let hex_digit = range 'a' 'f' <|> range 'A' 'F'
let oct_digit = range '0' '7'
let lexeme x = spaces >> x
let token s =
  let rec loop s i =
    if i >= String.length s
    then return s
    else exactly s.[i] >> loop s (i + 1)
  in
  lexeme (loop s 0)
(* ------------------------------ opal.ml END ------------------------------- *)


(* open Opal *)

type typename = Typename of string
type name = Name of string

type op = BinAdd | BinSub | BinMult | BinDiv | BinPower

type pattern = Pattern of typename * name list * exp

and pattern_expression = pattern * exp

(* some pseudocode here i am still not sure how exactly 
the type system works *)
and prog = Stmts of prog list
         | Assignment of exp * exp
         | Receive of name list * pattern_expression list
         | Send of exp * exp
and stmts = Stmts of prog list

and exp = BinOp of op * exp * exp
         | Call of exp * exp list
         | NewInstance of exp * exp list
         | Name of string
         | Number of int
         | String of string
         | Bool of bool
         | Typename of string
         | Array of exp list
         | Lambda of name list * stmts
         
exception Syntax_error
exception Runtime_error

let rec join separator = function
    | []    -> ""
    | [h]   -> h
    | h::t  -> h ^ separator ^ join separator t

let rec dumpop = function
    | BinAdd -> "+"
    | BinSub -> "-"
    | BinMult -> "*"
    | BinPower -> "**"
    | BinDiv -> "/";;


let rec dumpe = function
    | BinOp (op, l, r) -> "BinOp<" ^ (dumpop op) ^ "," ^ (dumpe l) ^ "," ^ (dumpe r) ^ ">"
    | Call (callee, args) -> "Call<" ^ (dumpe callee) ^ ",[" ^ (join "\n  " (List.map dumpe args)) ^ "]>"
    | NewInstance (class_, args) -> "NewInstance<" ^ (dumpe class_) ^ ",[" ^ (join "\n  " (List.map dumpe args)) ^ "]>"
    | Name s     -> "Variable<" ^ s ^ ">"
    | Typename t -> "Typename<" ^ t ^ ">"
    | Number n       -> "Number<" ^ (string_of_int n) ^ ">"
    | String n       -> "String<" ^ (string_of_int n) ^ ">"
    | Bool b      -> "Bool<" ^ (string_of_bool b) ^ ">"
    | Array e      -> "List<" ^ (join "\n  " (List.map dumpe e)) ^ "\n>"
    | Lambda (a, b)   -> "Lambda<" ^ (dumpe a) ^ ",\n" ^ (dump b) ^ "\n>"

let rec dump = function
    | Stmts elements      -> let s = join ", " (List.map dump elements) in "[" ^ s ^ "]"
    | Assignment (name, expr) -> "Assign<" ^ name ^ " = " ^ (dumpe expr) ^ ">"
    | Receive (args, patterns) -> "If<" ^ (join ", " (List.map dumpe args)) ^ "," ^ (join "\n  " (List.map dumppa patterns)) >> ">"
    | Send (pid, exp) -> "<- " ^ (dumpe pid) ^ ", " ^ (dumpe exp) ^ ""

let rec dumppa = function
    | PatternExpression (p, e) -> "@[" ^ (dumppb p) ^ " " ^ (dumpe e) "]"

let rec dumppb = function
    | Pattern (head, args) -> "@[" ^ (dumpe head) ^ " " ^ (join "  " (List.map dumpe args));;

(* val dump : prog list -> string = <fun> *)

(* parser *)

let reserved = [
  "true";
  "false";
  "if";
  "then";
  "else";
  "while";
  "do";
  "and";
  "or";
]

let ident = (spaces >> letter <~> many alpha_num) => implode >>= function
  | s when List.mem s reserved -> mzero
  | s -> return s

let number = spaces >> many1 digit => implode % int_of_string

let parens = between (token "(") (token ")")
let addop = token "+" >> return (fun x y -> PlusExp(x, y))
let subop = token "-" >> return (fun x y -> SubExp(x, y))
let mulop = token "*" >> return (fun x y -> MulExp(x, y))
let divop = token "/" >> return (fun x y -> DivExp(x, y))
let ltop  = token "<" >> return (fun x y -> LTExp(x, y))
let gtop  = token ">" >> return (fun x y -> GTExp(x, y))
let orop  = token "or"  >> return (fun x y -> OrExp(x, y))
let andop = token "and" >> return (fun x y -> AndExp(x, y))
let atom = (ident => (fun s -> Variable s))
       <|> (number => (fun x -> Number x))
       <|> (token "true" >> return (Bool true))
       <|> (token "false" >> return (Bool false))

let rec expr input = (chainl1 and_expr orop) input
and and_expr input = (chainl1 rop_expr andop) input
and rop_expr input = (chainl1 add_expr (ltop <|> gtop)) input
and add_expr input = (chainl1 mul_expr (addop <|> subop)) input
and mul_expr input = (chainl1 prm_expr (mulop <|> divop)) input
and prm_expr input = (parens expr <|> atom) input

let rec stmts input = (sep_by1 stmt (token ";") => (fun l -> Stmts l)) input
and stmt input = (if_stmt <|> while_stmt <|> assign_stmt) input
and if_stmt input =
  (token "if"   >> (* if *)
   expr         >>= fun pred ->
   token "then" >> (* then *)
   token "{"    >> (* { *)
   stmts        >>= fun thn ->
   token "}"    >> (* } *)
   token "else" >> (* else *)
   token "{"    >> (* { *)
   stmts        >>= fun els ->
   token "}"    >>
   return (IfElse (pred, thn, els))) input
and while_stmt input =
  (token "while" >> (* while *)
   expr          >>= fun guard ->
   token "do"    >> (* do *)
   token "{"     >> (* { *)
   stmts         >>= fun body ->
   token "}"     >>
   return (While (guard, body))) input
and assign_stmt input =
  (ident      >>= fun lhs ->
   token ":=" >>
   expr       >>= fun rhs ->
   return (Assign (lhs, rhs))) input

let prog = stmts << (spaces << eof ())
let parse_prog input = parse prog input

(* eval *)
let rec eval prog env =
  match prog with
    | Stmts [] -> ()
    | Stmts (x::xs) ->
        eval x env;
        eval (Stmts xs) env
    | Assign (lhs, rhs) ->
        let value = eval_aexp rhs env in
        Hashtbl.replace env lhs value
    | IfElse (pred, thn, els) ->
        if (eval_bexp pred env) then
          eval thn env
        else
          eval els env
    | While (guard, body) ->
        let rec loop () =
          if (eval_bexp guard env) then
            begin
              eval body env;
              loop ()
            end
          else ()
        in
        loop ()

and eval_aexp aexp env =
  match aexp with
    | PlusExp (l, r) ->
        let l' = eval_aexp l env
        and r' = eval_aexp r env in
        l' + r'
    | SubExp (l, r) ->
        let l' = eval_aexp l env
        and r' = eval_aexp r env in
        l' - r'
    | MulExp (l, r) ->
        let l' = eval_aexp l env
        and r' = eval_aexp r env in
        l' * r'
    | DivExp (l, r) ->
        let l' = eval_aexp l env
        and r' = eval_aexp r env in
        l' / r'
    | Variable x -> Hashtbl.find env x
    | Number n -> n
    | _ -> raise Runtime_error

and eval_bexp bexp env =
  match bexp with
    | LTExp (l, r) ->
        let l' = eval_aexp l env
        and r' = eval_aexp r env in
        l' < r'
    | GTExp (l, r) ->
        let l' = eval_aexp l env
        and r' = eval_aexp r env in
        l' > r'
    | AndExp (l, r) ->
        let l' = eval_bexp l env
        and r' = eval_bexp r env in
        l' && r'
    | OrExp (l, r) ->
        let l' = eval_bexp l env
        and r' = eval_bexp r env in
        l' || r'
    | Bool b -> b
    | _ -> raise Runtime_error

let () =
  let src = LazyStream.of_channel stdin in
  match parse_prog src with
  | None -> raise Syntax_error
  | Some prog ->
      let () = Printf.printf "%s" (dump prog)
    in
      let env = Hashtbl.create 16 in
      eval prog env;
      let pairs = Hashtbl.fold (fun k v acc -> (k, v) :: acc) env [] in
      let pairs' = List.sort (fun (k1, _) (k2, _) -> compare k1 k2) pairs in
      List.iter (fun (k, v) -> Printf.printf "%s %d\n" k v) pairs'
