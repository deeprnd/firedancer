/**
 * Exclude agave code and whatever else we don't want to analyze.
 *
 * In production databases the source root is the repo root, so Firedancer
 * files have relative paths starting with "src/".  In CodeQL test databases
 * the source root is the individual test directory, so the test .c files have
 * bare filenames with no directory component.  Both cases are included.
 */
import cpp
predicate included(Location loc) {
  loc.getFile().getRelativePath().prefix(4) = "src/" or
  // Test databases: bare filename with no leading directory.
  not loc.getFile().getRelativePath().matches("%/%")
}
