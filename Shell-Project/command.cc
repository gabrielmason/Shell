/*
 * CS252: Shell project
 *
 * Template file.
 * You will need to add more code here to execute the command table.
 *
 * NOTE: You are responsible for fixing any bugs this code may have!
 *
 * DO NOT PUT THIS PROJECT IN A PUBLIC REPOSITORY LIKE GIT. IF YOU WANT 
 * TO MAKE IT PUBLICALLY AVAILABLE YOU NEED TO REMOVE ANY SKELETON CODE 
 * AND REWRITE YOUR PROJECT SO IT IMPLEMENTS FUNCTIONALITY DIFFERENT THAN
 * WHAT IS SPECIFIED IN THE HANDOUT. WE OFTEN REUSE PART OF THE PROJECTS FROM  
 * SEMESTER TO SEMESTER AND PUTTING YOUR CODE IN A PUBLIC REPOSITORY
 * MAY FACILITATE ACADEMIC DISHONESTY.
 */

#include <cstdio>
#include <cstdlib>

#include <iostream>

#include "command.hh"
#include "shell.hh"
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <string.h>
#include <string>
#include <stdlib.h>
#include <limits.h>

void myunputc(int c);

int last_background_pid = 0;


Command::Command() {
    // Initialize a new vector of Simple Commands
    _simpleCommands = std::vector<SimpleCommand *>();

    _outFile = NULL;
    _inFile = NULL;
    _errFile = NULL;
    _background = false;
}

void Command::insertSimpleCommand( SimpleCommand * simpleCommand ) {
    // add the simple command to the vector
    _simpleCommands.push_back(simpleCommand);
}

void Command::clear() {
    // deallocate all the simple commands in the command vector
    for (auto simpleCommand : _simpleCommands) {
        delete simpleCommand;
    }

    // remove all references to the simple commands we've deallocated
    // (basically just sets the size to 0)
    _simpleCommands.clear();

    if ( _outFile ) {
        delete _outFile;
    }
    _outFile = NULL;

    if ( _inFile ) {
        delete _inFile;
    }
    _inFile = NULL;

    if ( _errFile ) {
        delete _errFile;
    }
    _errFile = NULL;

    _background = false;
}

void Command::print() {
    printf("\n\n");
    printf("              COMMAND TABLE                \n");
    printf("\n");
    printf("  #   Simple Commands\n");
    printf("  --- ----------------------------------------------------------\n");

    int i = 0;
    // iterate over the simple commands and print them nicely
    for ( auto & simpleCommand : _simpleCommands ) {
        printf("  %-3d ", i++ );
        simpleCommand->print();
    }

    printf( "\n\n" );
    printf( "  Output       Input        Error        Background\n" );
    printf( "  ------------ ------------ ------------ ------------\n" );
    printf( "  %-12s %-12s %-12s %-12s\n",
            _outFile?_outFile->c_str():"default",
            _inFile?_inFile->c_str():"default",
            _errFile?_errFile->c_str():"default",
            _background?"YES":"NO");
    printf( "\n\n" );
}

void Command::execute() {
    // Don't do anything if there are no simple commands
    if ( _simpleCommands.size() == 0 ) {
        Shell::prompt();
        return;
    }


    if (!strcmp(_simpleCommands[0]->_arguments[0]->c_str(), "exit")) {
      if (isatty(0)) {
        printf("Good bye!\n");
      }
      exit(1);
    }

    if (!strcmp(_simpleCommands[0]->_arguments[0]->c_str(), "setenv")) {
      const char * A = _simpleCommands[0]->_arguments[1]->c_str();
      const char * B = _simpleCommands[0]->_arguments[2]->c_str();
      setenv(A, B, 1);
      clear();
      Shell::prompt();
      return;
    }

    if (!strcmp(_simpleCommands[0]->_arguments[0]->c_str(), "unsetenv")) {
      const char * A = _simpleCommands[0]->_arguments[1]->c_str();
      unsetenv(A);
      clear();
      Shell::prompt();
      return;
    }

    if (!strcmp(_simpleCommands[0]->_arguments[0]->c_str(), "cd")) {
      if (_simpleCommands[0]->_arguments.size() > 1) {
        const char * dir = _simpleCommands[0]->_arguments[1]->c_str();
        if (chdir(dir) < 0) {
          fprintf(stderr, "cd: can't cd to %s\n", dir);
        }
      } else {
        chdir(getenv("HOME"));
      }
      clear();
      Shell::prompt();
      return;
    }


    // Print contents of Command data structure

    //print();

    // Add execution here
    // For every simple command fork a new process

    int tmpin = dup(0);
    int tmpout = dup(1);
    int tmperr = dup(2);
    int fdin;
    if (_inFile) {
      fdin = open(_inFile->c_str(), O_RDONLY);
    } else {
      fdin = dup(tmpin);
    }
    int fderr;
    int fdout;
    int numSimple = _simpleCommands.size();
    int ret;
    for (int i = 0; i < numSimple; i++) {
      dup2(fdin, 0);
      close(fdin);
      if (i == numSimple - 1) { //last command
        if (_outFile) {
          if (_append) {
            fdout = open(_outFile->c_str(), O_CREAT | O_WRONLY | O_APPEND, 0664);
          } else {
            fdout = open(_outFile->c_str(), O_CREAT | O_WRONLY | O_TRUNC, 0664);
          }
        } else {
          fdout = dup(tmpout);
        }

        if (_errFile) {
          if (_append) {
            fderr = open(_errFile->c_str(), O_CREAT | O_WRONLY | O_APPEND, 0664);
          } else {
            fderr = open(_errFile->c_str(), O_CREAT | O_WRONLY | O_TRUNC, 0664);
          }
        } else {
          fderr = dup(tmperr);
        }
        setenv("_", _simpleCommands[i]->_arguments[_simpleCommands[i]->_arguments.size() - 1]->c_str(), 1);

      } else { //not last command
        int fdpipe[2];
        pipe(fdpipe);
        fdout = fdpipe[1];
        fdin = fdpipe[0];
      }
      dup2(fderr, 2);
      close(fderr);

      dup2(fdout, 1);
      close(fdout);
      ret = fork();
      if (ret == 0) {
        if (!strcmp(_simpleCommands[i]->_arguments[0]->c_str(), "printenv")) {
          char **p = environ;
          while (*p != NULL) {
            printf("%s\n", *p);
            p++;
          }
          exit(0);
        }
        int numArgs = _simpleCommands[i]->_arguments.size();
        char ** arguments = new char*[numArgs + 1];
        for(int j = 0; j < numArgs; j++) {
          arguments[j] = (char *) _simpleCommands[i]->_arguments[j]->c_str();
        }
        arguments[numArgs] = NULL;
        execvp(_simpleCommands[i]->_arguments[0]->c_str(), arguments);
        perror("execvp");
        exit(1);
      }
    }
    dup2(tmpin, 0);
    dup2(tmpout, 1);
    dup2(tmperr, 2);
    close(tmpin);
    close(tmpout);
    close(tmperr);

    if (!_background) {
      int ret_code;
      waitpid(ret, &ret_code, 0);
      std::string ret_code_string = std::to_string(WEXITSTATUS(ret_code));
      setenv("?", ret_code_string.c_str(), 1);
    } else {
      std::string background_pid_string = std::to_string(ret);
      setenv("!", background_pid_string.c_str(), 1);
    }



    // Clear to prepare for next command
    clear();

    // Print new prompt
    Shell::prompt();
}

void Command::redirect(int type, std::string * file_name) {
  switch(type) {
    case 0:
      _inFile = file_name;
      break;
    case 1:
      if (_outFile) {
        printf("Ambiguous output redirect.\n");
        exit(1);
      } else {
        _outFile = file_name;
      }
      break;
    case 2:
      if (_errFile) {
        printf("Ambiguous error redirect.\n");
        exit(1);
      } else {
        _errFile = file_name;
      }
  }
}

SimpleCommand * Command::_currentSimpleCommand;
