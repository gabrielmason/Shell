
%{

#include <cstring>
#include "y.tab.hh"
#include <sys/wait.h>
#include <string.h>
#include "shell.hh"
#include <unistd.h>


static  void yyunput (int c,char *buf_ptr  );

void myunputc(int c) {
  unput(c);
}

extern "C" char * read_line();

int mygetc(FILE * f) {
  static char *p;
  char ch;

  if (!isatty(0)) {
  // stdin is not a tty. Call real getc
    return getc(f);
  }

  // stdin is a tty. Call our read_line.
  if (p==NULL || *p == 0) {
    char * s = read_line();
    p = s;
  }

  ch = *p;
  p++;

  return ch;
}

#undef getc
#define getc(f) mygetc(f)

%}

%option noyywrap

%%

\n {
  return NEWLINE;
}

[ \t] {
  /* Discard spaces and tabs */
}

">" {
  return GREAT;
}

"<" {
  return LESS;
}

">>" {
  return GREATGREAT;
}

"&" {
  return AMPERSAND;
}

"|" {
  return PIPE;
}

">&" {
  return GREATAND;
}

"2>" {
  return TWOGREAT;
}

">>&" {
  return GREATGREATAND;
}



~[^ \n\t]* {
  //Tilde expansion
  std::string text = std::string(yytext);
  std::string home_dir = getenv("HOME");
  if (!strcmp(yytext, "~")) {
    yylval.cpp_string = new std::string(home_dir);
  } else {
    if (text[1] == '/') {
      text = home_dir + text.substr(1, -1);
    } else {
      text = std::string("/homes/") + text.substr(1,-1);
    }
    yylval.cpp_string = new std::string(text);
  }
  return WORD;
}


[^ \t\n]*\\[^ \t\n]* {
  //escape characters
  std::string for_len = std::string(yytext);
  int length = for_len.size();
  char * text = strdup(yytext);
  int i = 0;
  int j = 0;
  char * new_text = new char[length];
  while (text[i] != 0) {
    if (text[i] == '\\') {
      i++;
    }
    if (text[i] != 0) {
      new_text[j] = text[i];
      j++;
    }
    i++;
  }
  yylval.cpp_string = new std::string(new_text);
  return WORD;
}

[^ \n]*$\{[^ \}\n]+\}([^ \n]*|$\{[^ \}\n]+\})* {
  //environment variable expansion
  char * text = yytext;
  std::string result = "";
  int i = 0;
  char cur = text[i];
  while (cur != 0) {
    if ((cur == '$') && (text[i + 1] == '{')) {
      std::string toExpand = "";
      std::string expanded;
      int j = i + 2;
      while (text[j] != '}') {
        toExpand += text[j];
        j++;
      }
      i = j;
      expanded = getenv(toExpand.c_str());
      result.append(expanded);
    } else {
      result += text[i];
    }
    i++;
    cur = text[i];
  }
  yylval.cpp_string = new std::string(result);
  return WORD;
}


$\([^\n]*\) {
  //subshell
  std::string command = std::string(yytext);
  command = command.substr(2, command.size() - 3);
  command = command.append("\nexit\n");

  int pin[2];
  int pout[2];
  int tmpin;
  int tmpout;
  tmpin = dup(0);
  tmpout = dup(1);
  pipe(pin);
  pipe(pout);
  dup2(pin[0], 0); //redirect input from pin[0]
  dup2(pout[1], 1); //redirect output to pout[1]
  close(pin[0]);
  close(pout[1]);
  write(pin[1], command.c_str(), command.size());
  close(pin[1]);

  int ret = fork();
  if (ret == 0) {
    char ** arguments = new char*[2];
    arguments[0] = (char*) "/proc/self/exe";
    arguments[1] = NULL;
    execvp(arguments[0], arguments);
    exit(1);
  }
  dup2(tmpin, 0);
  dup2(tmpout, 1);
  close(tmpin);
  close(tmpout);
  char* sub_out = new char[2048];
  int numRead = read(pout[0], sub_out, 2048);
  close(pout[0]);
  for (int i = numRead - 1; i >= 0; i--) {
    if (sub_out[i] == '\n') {
      sub_out[i] = ' ';
    }
    myunputc(sub_out[i]);
  }
}



source\ [^ \t\n]* {
  std::string text = std::string(yytext);
  const char * file_name = std::string(text.substr(7, text.size() - 7)).c_str();
  FILE * fp = fopen(file_name, "r+");
  if (fp) {
    fputc('\n', fp);
    yypush_buffer_state(yy_create_buffer(fp, YY_BUF_SIZE));
    BEGIN(INITIAL);
    yyparse();
    yypop_buffer_state();
    fclose(fp);
  }
}


[^ \|>\t\n][^ \|>\t\n]*  {
  /* Assume that file names have only alpha chars */

  yylval.cpp_string = new std::string(yytext);
  return WORD;
}


\"[^\n\"]*\" {
  std::string text = std::string(yytext);
  yylval.cpp_string = new std::string(text.substr(1, text.size() - 2));
  return WORD;
}


