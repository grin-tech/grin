module Transformations.SyntaxSpec where

import Control.DeepSeq

import Grin.Grin
import Grin.Syntax (Exp)
import qualified Grin.ExtendedSyntax.Syntax as New (Exp)
import Transformations.Syntax

import Test.Hspec
import Test.QuickCheck
import Test.Hspec.QuickCheck

import Test.Assertions
import Test.ExtendedSyntax.Old.Test()
import qualified Test.ExtendedSyntax.Old.Grammar as G

runTests :: IO ()
runTests = hspec spec

spec :: Spec
spec = describe "Syntax transformation QuickCheck tests" $ do
         prop "Old is always convertible to New" $
           convertibleToNew
         prop "Old is always convertible to New then back to Old" $
           roundtripConvertibleOld

-- NOTE: The conversion itself is the proof that it is convertible
-- QUESTION: There must be a better way to do this
-- ANSWER: The conversion function could an Either
convertibleToNew :: G.Exp -> Bool
convertibleToNew exp = force (convertToNew $ G.asExp exp) `seq` True

roundtripConvertibleOld :: G.Exp -> Bool
roundtripConvertibleOld exp = force (convertToOld $ convertToNew $ G.asExp exp) `seq` True where

  convertToOld :: New.Exp -> Exp
  convertToOld = convert