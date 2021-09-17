
/*
 * CS-252
 * shell.y: parser for shell
 *
 * This parser compiles the following grammar:
 *
 *	cmd [arg]* [> filename]
 *
 * you must extend it to understand the complete shell grammar
 *
 */

%code requires 
{
#include <string>

#if __cplusplus > 199711L
#define register      // Deprecated in C++11 so remove the keyword
#endif
}

%union
{
  char        *string_val;
  // Example of using a c++ type in yacc
  std::string *cpp_string;
}

%token <cpp_string> WORD
%token NOTOKEN GREAT NEWLINE PIPE LESS AMPERSAND GREATAND GREATGREAT TWOGREAT GREATGREATAND

%{
//#define yylex yylex
#include <cstdio>
#include "shell.hh"
#include <vector>
#include <algorithm>
#include <unistd.h>
#include <string.h>
#include <string>
#include <regex.h>
#include <dirent.h>
#include <sys/types.h>
#include <iterator>

void yyerror(const char * s);
void expandWildcardsIfNecessary(char * arg);
void expandWildcard(char * prefix, char * suffix);

bool compare (char * first, char * second);

std::vector<char *> entries = std::vector<char *>();
int yylex();

%}

%%

goal:
  commands
  ;

commands:
  command
  | commands command
  ;

command:
  simple_command
  ;

simple_command:
  pipe_list iomodifier_list background_opt NEWLINE {
    //printf("   Yacc: Execute command\n");
    Shell::_currentCommand.execute();
  }
  | NEWLINE {
    Shell::_currentCommand.execute();
  }
  | error NEWLINE { yyerrok; }
  ;


command_and_args:
  command_word argument_list {
    Shell::_currentCommand.
    insertSimpleCommand( Command::_currentSimpleCommand );
  }
  ;

argument_list:
  argument_list argument
  | /* can be empty */
  ;

argument:
  WORD {
    //printf("   Yacc: insert argument \"%s\"\n", $1->c_str());
    if (strchr($1->c_str(), '*') == NULL) {
      Command::_currentSimpleCommand->insertArgument($1);
    } else {
      char * prefix = (char *) "";
      expandWildcard(prefix, (char *) $1->c_str());
      std::sort(entries.begin(), entries.end(), compare);
      for (int i = 0; i < entries.size(); i++) {
        Command::_currentSimpleCommand->insertArgument(new std::string(entries[i]));
      }
      entries.clear();
    }
  }
  ;

command_word:
  WORD {
    //printf("   Yacc: insert command \"%s\"\n", $1->c_str());
    Command::_currentSimpleCommand = new SimpleCommand();
    Command::_currentSimpleCommand->insertArgument( $1 );
  }
  ;

pipe_list:
  pipe_list PIPE command_and_args
  | command_and_args
  ;

iomodifier_opt:
  GREAT WORD {
    //printf("   Yacc: insert output \"%s\"\n", $2->c_str());
    Shell::_currentCommand.redirect(1, $2);
  }
  | GREATAND WORD {
    //printf("   Yacc: insert output and error \"%s\"\n", $2->c_str());
    Shell::_currentCommand.redirect(1, $2);
    Shell::_currentCommand.redirect(2, new std::string($2->c_str()));

  }
  | GREATGREATAND WORD {
    //printf("   Yacc: append output and error \"%s\"\n", $2->c_str());
    Shell::_currentCommand.redirect(1,$2);
    Shell::_currentCommand.redirect(2, new std::string($2->c_str()));
    Shell::_currentCommand._append = true;

  }
  | GREATGREAT WORD {
    //printf("   Yacc: append output \"%s\"\n", $2->c_str());
    Shell::_currentCommand.redirect(1, $2);
    Shell::_currentCommand._append = true;

  }
  | LESS WORD {
    //printf("   Yacc: get input \"%s\"\n", $2->c_str());
    Shell::_currentCommand.redirect(0, $2);
  }
  | TWOGREAT WORD {
    //printf("   Yacc: insert error \"%s\"\n", $2->c_str());
    Shell::_currentCommand.redirect(2, $2);
  }
  ;

iomodifier_list:
  iomodifier_list iomodifier_opt
  |
  ;

background_opt:
  AMPERSAND {
    //printf("   Yacc: background mode\n");
    Shell::_currentCommand._background = true;
  }
  |
  ;

%%

void
yyerror(const char * s)
{
  fprintf(stderr,"%s", s);
// fprintf(stderr, "line %d: %s\n", yyrline, s);
}


void expandWildcard(char * old_prefix, char * suffix) {

  if (suffix[0] == 0) { //suffix is empty
    entries.push_back(strdup(old_prefix));
    return;
  }

  char prefix[1024];

  if (old_prefix[0] == 0 && suffix[0] == '/') {
    suffix++;
    sprintf(prefix, "%s/", old_prefix);
  } else if (old_prefix[0] == 0 && suffix[0] != '/') {
    strcpy(prefix, old_prefix);
  } else if (old_prefix[0] != 0) {
    sprintf(prefix, "%s/", old_prefix);
  }

  char * s = strchr(suffix, '/');
  char comp[1024];


  if (s != NULL) {
    strncpy(comp, suffix, (size_t) (s - suffix));
    comp[s - suffix] = 0;
    suffix = s + 1;
  } else {
    strcpy(comp, suffix);
    suffix = suffix + strlen(suffix);
  }

  char newPrefix[1024];
  if (prefix[0] == 0) {
    strcpy(newPrefix, comp);
  } else {
    sprintf(newPrefix, "%s/%s", old_prefix, comp);
  }

  if (strchr(comp, '*') == NULL && strchr(comp, '?') == NULL) { //component doesn't have wildcards
    expandWildcard(newPrefix, suffix);
    return;
  }

  //component has wildcards; convert to regex

  char * reg = (char*) malloc(2 * strlen(comp) + 10);
  char * a = comp;
  char * r = reg;
  *r = '^';
  r++;

  while (*a) {
    if (*a == '*') {
      *r = '.';
      r++;
      *r = '*';
      r++;
    } else if (*a == '?') {
      *r = '.';
      r++;
    } else if (*a == '.') {
      *r = '\\';
      r++;
      *r = '.';
      r++;
    } else {
      *r = *a;
      r++;
    }
      a++;
  }

  *r = '$';
  r++;
  *r = 0;

  //compile regex

  regex_t re;
  int check = regcomp(&re, reg, REG_EXTENDED|REG_NOSUB);
  if (check != 0) {
    perror("Bad regex");
    return;
  }

  char * dir_string;
  if (prefix[0] == 0) {
    dir_string = (char *) ".";
  } else {
    dir_string = prefix;
  }

  DIR * dir = opendir(dir_string);
  if (dir == NULL) {
    return;
  }
  struct dirent * ent;

  bool matched;
  while ((ent = readdir(dir)) != NULL) {
    if(regexec(&re, ent->d_name, 1, NULL, 0) == 0) {
      matched = true;
      if (prefix[0] == 0) {
        strcpy(newPrefix, ent->d_name);
      } else {
        sprintf(newPrefix, "%s/%s", old_prefix, ent->d_name);
      }

      if (ent->d_name[0] == '.') {
        if (comp[0] == '.') {
          expandWildcard(newPrefix, suffix);
        }
      } else {
        expandWildcard(newPrefix, suffix);
      }
    }
  }
  /*
  if (!matched) {
    expandWildcard(newPrefix, comp);
  }
  */
  closedir(dir);
  regfree(&re);
  free(reg);

}


void expandWildcardsIfNecessary(char * arg) {

  char * reg = (char*) malloc(2 * strlen(arg) + 10);
  char * a = arg;
  char * r = reg;
  *r = '^';
  r++;

  while (*a) {
    if (*a == '*') {
      *r = '.';
      r++;
      *r = '*';
      r++;
    } else if (*a == '?') {
      *r = '.';
      r++;
    } else if (*a == '.') {
      *r = '\\';
      r++;
      *r = '.';
      r++;
    } else {
      *r = *a;
      r++;
    }
      a++;
  }

  *r = '$';
  r++;
  *r = 0;

// 2. compile regular expression

  regex_t re;
  int check = regcomp(&re, reg, REG_EXTENDED|REG_NOSUB);
  if (check != 0) {
    perror("Bad regex");
    return;
  }

  // 3. List directory and add as arguments the entries
  // that match the regular expression

  DIR * dir = opendir(".");
  if (dir == NULL) {
    perror("opendir");
    return;
  }
  struct dirent * ent;
  regmatch_t match;

  std::vector<std::string> entries;

  while ((ent = readdir(dir))!= NULL) {
    //Check if name matches
    if (regexec(&re, ent->d_name, 1, &match, 0) == 0) {
      if (ent->d_name[0] == '.') {
       if (arg[0] == '.') {
         entries.push_back(std::string(ent->d_name));
        }
      } else {
        entries.push_back(std::string(ent->d_name));
      }
    }
  }

  closedir(dir);
  regfree(&re);
  std::sort(entries.begin(), entries.end());

  // Add arguments
  for (int i = 0; i < entries.size(); i++) {
    Command::_currentSimpleCommand->insertArgument(new std::string(entries[i]));
  }

}

bool compare (char * first, char * second) {
  return strcmp(first, second) < 0;
}



#if 0
main()
{
  yyparse();
}
#endif
