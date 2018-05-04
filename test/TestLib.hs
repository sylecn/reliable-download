import RD.Lib (sha1sumOnBytes)

import System.Exit
import Test.HUnit

test_dumb = TestCase (assertEqual "dumb test" True True)

test_sha1sumOnBytes =
    TestList
    ["adc83b19e793491b1c6ea0fd8b46cd9f32e592fc" ~=? (sha1sumOnBytes "\n")
    ,"81fe8bfe87576c3ecb22426f8e57847382917acf" ~=? (sha1sumOnBytes "abcd")
    ]

allTests = TestList [test_dumb
                    ,test_sha1sumOnBytes]

main :: IO a
main = do
  counts <- runTestTT allTests
  if errors counts + failures counts > 0 then
      exitFailure
  else
      exitSuccess
