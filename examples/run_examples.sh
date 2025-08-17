#!/usr/bin/env bash

for file in examples/*; do
  echo '$' $file

  if [ "$file" = "examples/pipe.gene" ]; then
    echo TEST | $file
  elif [ "$file" = "examples/repl.gene" ] ||
       [ "$file" = "examples/repl-on-demand.gene" ] ||
       [ "$file" = "examples/repl-on-error.gene" ] ||
       [ "$file" = "examples/http_todo_app.gene" ] ||
       [ "$file" = "examples/http_todo_app_repl.gene" ] ||
       [ "$file" = "examples/http_server.gene" ]; then
    echo "SKIPPED!"
  elif [ -f "$file" ] && [ -x "$file" ]; then
    "$file"
  else
    echo "NOT EXECUTABLE!"
  fi

  echo
  echo
done
