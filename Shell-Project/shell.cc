#include <cstdio>

#include "shell.hh"
#include <unistd.h>
#include <stdio.h>
#include <signal.h>
#include <string.h>
#include <stdlib.h>
#include <sys/wait.h>

int yyparse(void);

void Shell::prompt() {
  if (isatty(0)) {
    printf("myshell>");
    fflush(stdout);
  }
}

extern "C" void handle(int sig) {
  if (sig == SIGINT) {
    //fprintf(stderr, "\nsig:%d  process terminated by signal\n", sig);
    Shell::prompt();
    //exit(1); // remove this line later, this is just so I can exit in case of emergency
  }
  if (sig == SIGCHLD) {
    int pid;
    while ((pid = waitpid(-1, NULL, WNOHANG)) > 0);
    if (isatty(0) && pid > 0) {
      printf("[%d] exited\n", pid);
    }
  }
}

int main(int, char **argv) {

  struct sigaction sa;
  sa.sa_handler = handle;
  sigemptyset(&sa.sa_mask);
  sa.sa_flags = SA_RESTART;

  Shell::prompt();

  if (sigaction(SIGINT, &sa, NULL)) {
    perror("sigaction");
    exit(2);
  }
  if (sigaction(SIGCHLD, &sa, NULL)) {
    perror("sigaction");
//    exit(-1);
  }

  //set SHELL and ? environment variable
  std::string pid = std::to_string(getpid());
  setenv("$", pid.c_str(), 1);
  char * expanded_directory = realpath(argv[0], NULL);
  setenv("SHELL", expanded_directory , 1);

  yyparse();

}

Command Shell::_currentCommand;
