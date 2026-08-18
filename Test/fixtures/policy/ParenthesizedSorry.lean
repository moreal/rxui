-- Lean's `hasSorry` diagnostic must catch forms that lexical defense can miss.
example : True := (sorry)
