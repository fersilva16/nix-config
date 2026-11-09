/*
 * fda-exec PROGRAM [ARGS...]
 *
 * Runs PROGRAM as a child and waits for it instead of exec'ing it: macOS
 * attributes a child's file access to its parent, so a Full Disk Access
 * grant for this binary covers whatever it starts. Signals are forwarded so
 * launchd can still stop the child, and the child's exit status becomes ours.
 */
#include <errno.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <string.h>
#include <sys/wait.h>

extern char **environ;
static volatile pid_t child = 0;

static void forward(int sig) {
  if (child > 0)
    kill(child, sig);
}

int main(int argc, char **argv) {
  if (argc < 2) {
    fprintf(stderr, "usage: %s program [args...]\n", argv[0]);
    return 64;
  }

  struct sigaction sa;
  memset(&sa, 0, sizeof sa);
  sa.sa_handler = forward;
  sa.sa_flags = SA_RESTART;
  sigemptyset(&sa.sa_mask);
  const int forwarded[] = {SIGHUP, SIGINT, SIGQUIT, SIGTERM, SIGUSR1, SIGUSR2};
  for (size_t i = 0; i < sizeof forwarded / sizeof *forwarded; i++)
    sigaction(forwarded[i], &sa, NULL);

  pid_t pid;
  int err = posix_spawn(&pid, argv[1], NULL, NULL, argv + 1, environ);
  if (err != 0) {
    fprintf(stderr, "fda-exec: %s: %s\n", argv[1], strerror(err));
    return 127;
  }
  child = pid;

  int status;
  while (waitpid(pid, &status, 0) < 0) {
    if (errno != EINTR) {
      perror("fda-exec: waitpid");
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
