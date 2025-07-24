import gene/types

import ./helpers

# How packaging work
#
# If a package will store one or more global reference, it should mention the names
# in package.gene.
# Package can specify whether multiple copies are allowed.
#   * By default, multiple copies are allowed
#   * If a package define/modify global variable, multiple copies are disallowed by
#     default, but can be overwritten. It'll cause undefined behaviour.
#
# Search order - can be changed to support Ruby gemset like feature.
#   * <APP DIR>/packages
#   * <USER HOME>/packages
#   * <RUNTIME DIR>/packages
#
# packages directory structure
# packages/
#   x/
#     1.0/
#     <GIT COMMIT>/
#

test_interpreter """
  $pkg/.name
""", "gene"

test_interpreter """
  ($dep "my-lib" ^path "example-projects/my-lib")
  (import x from "index" ^pkg "my-lib")
  (x)
""", 1
