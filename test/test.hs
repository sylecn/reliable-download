import qualified TestLib
-- import qualified TestApi

import System.Exit
import Test.HUnit

allTests = TestList [TestLib.allTests
                    ]

main :: IO a
main = do
  counts <- runTestTT allTests
  if errors counts + failures counts > 0 then
      exitFailure
  else
      exitSuccess
