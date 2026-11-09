/*
 * nix-fda gc|optimise
 *
 * Holds the Full Disk Access grant for Nix's scheduled store maintenance, so
 * it must never lend that grant to anything else. It runs only the commands
 * compiled into nix-fda-commands.h, never a program its caller names, and
 * only for root. The child gets a fixed environment, not the caller's.
 *
 * It waits for the child instead of exec'ing it: macOS attributes a child's
 * file access to its parent, so the child works under this binary's grant.
 * Signals are forwarded so launchd can still stop the child, and the child's
 * exit status becomes ours.
 */
#include <errno.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

#include "nix-fda-commands.h"

static char *const child_env[] = {
    "PATH=/usr/bin:/bin:/usr/sbin:/sbin",
    "HOME=/var/root",
    "NIX_REMOTE=local",
    NULL,
};

static volatile pid_t child = 0;

static void forward(int sig) {
  if (child > 0)
    kill(child, sig);
}

int main(int argc, char **argv) {
  if (getuid() != 0 || geteuid() != 0) {
    fputs("nix-fda: refusing to run as a non-root user\n", stderr);
    return 77;
  }

  char *const *command;
  if (argc == 2 && strcmp(argv[1], "gc") == 0)
    command = gc_argv;
  else if (argc == 2 && strcmp(argv[1], "optimise") == 0)
    command = optimise_argv;
  else {
    fputs("usage: nix-fda gc|optimise\n", stderr);
    return 64;
  }

  struct sigaction sa;
  memset(&sa, 0, sizeof sa);
  sa.sa_handler = forward;
  sa.sa_flags = SA_RESTART;
  sigemptyset(&sa.sa_mask);
  const int forwarded[] = {SIGHUP, SIGINT, SIGQUIT, SIGTERM};
  for (size_t i = 0; i < sizeof forwarded / sizeof *forwarded; i++)
    sigaction(forwarded[i], &sa, NULL);

  pid_t pid;
  int err = posix_spawn(&pid, command[0], NULL, NULL, command, child_env);
  if (err != 0) {
    fprintf(stderr, "nix-fda: %s: %s\n", command[0], strerror(err));
    return 127;
  }
  child = pid;

  int status;
  while (waitpid(pid, &status, 0) < 0) {
    if (errno != EINTR) {
      perror("nix-fda: waitpid");
      return 1;
    }
  }
  if (WIFEXITED(status))
    return WEXITSTATUS(status);
  if (WIFSIGNALED(status)) {
    signal(WTERMSIG(status), SIG_DFL);
    raise(WTERMSIG(status));
  }
  return 1;
}
