import Lake

open Lake DSL

package leanrx where
  version := v!"0.1.0"

lean_lib LeanRx

@[default_target]
lean_exe leanrx_test where
  root := `Test.Main
