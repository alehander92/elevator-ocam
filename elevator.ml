let main () =
  print_string "elevator ~ ";
  flush stdout;
  let stream = Lexer.lex (Stream.of_channel stdin) in

  TopLevel.main_loop stream;
;;

main()
