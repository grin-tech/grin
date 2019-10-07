{-# LANGUAGE LambdaCase      #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE QuasiQuotes     #-}
module AbstractInterpretation.ExtendedSyntax.SharingSpec where

import Data.Set (Set)
import qualified Data.Set as Set

import qualified Grin.TH as Old

import Test.Hspec
import Grin.ExtendedSyntax.Grin
import Grin.ExtendedSyntax.TH
import Grin.ExtendedSyntax.Pretty
import Grin.ExtendedSyntax.PrimOpsPrelude

import AbstractInterpretation.ExtendedSyntax.Reduce
import AbstractInterpretation.ExtendedSyntax.Sharing.CodeGen
import AbstractInterpretation.ExtendedSyntax.Sharing.Result

import Transformations.ExtendedSyntax.Conversion (convertToNew)



runTests :: IO ()
runTests = hspec spec

spec :: Spec
spec = describe "Sharing analysis" $ do
  it "has not changed for sum simple." $ do
    let result = calcSharedLocations testProgram
    let expected = Set.fromList [0,1,4,5]
    result `shouldBe` expected

  it "finds non-transitive shared locations" $ do
    -- A sharing is calculated via for non-linear variables
    let code = [prog|
          main =
            one <- pure (COne)
            l0 <- store one
            l1 <- store one
            _1 <- update l0 one
            _2 <- fun l0
            v <- fetch l0
            pure ()
        |]
    let result = calcSharedLocations code
    let expected = Set.fromList [0]
    result `shouldBe` expected

  it "finds location based transitive shared location" $ do
    let code = [prog|
          main =
            one <- pure (COne)
            l0 <- store one
            two <- pure (CTwo l0)
            l1 <- store two
            _1 <- update l0 one
            _2 <- fun l1
            v <- fetch l1
            pure ()
        |]
    let result = calcSharedLocations code
    let expected = Set.fromList [0,1]
    result `shouldBe` expected

  it "finds location based on transitive non-linear var" $ do
    let code = [prog|
          main =
            one <- pure (COne)
            l0 <- store one
            l1 <- store one
            _1 <- update l0 one
            l2 <- pure l1
            v <- fetch l2
            _2 <- fun l2
            pure ()
        |]
    let result = calcSharedLocations code
    let expected = Set.fromList [1]
    result `shouldBe` expected

  it "finds location fetched twice inside a node with as-pattern" $ do
    let code = [prog|
          main =
            one <- pure (COne)
            l0 <- store one
            two <- pure (CTwo l0)
            l1 <- store two
            _1@(CTwo l2) <- fetch l1
            _2 <- fetch l2
            _2 <- fetch l2
            pure ()
        |]
    let result = calcSharedLocations code
    let expected = Set.fromList [0]
    result `shouldBe` expected

calcSharedLocations :: Exp -> Set Loc
calcSharedLocations = _sharedLocs . calcSharingResult

calcSharingResult :: Exp -> SharingResult
calcSharingResult prog
  | (shProgram, shMapping) <- codeGen prog
  , computer <- _airComp . evalAbstractProgram $ shProgram
  , shResult <- toSharingResult shMapping computer
  = shResult

testProgram :: Exp
-- The syntax conversion preserves the abstract heap layout
testProgram = withPrimPrelude . convertToNew $ [Old.prog|
    grinMain = t1 <- store (CInt 1)
               t2 <- store (CInt 10000)
               t3 <- store (Fupto t1 t2)
               t4 <- store (Fsum t3)
               (CInt r') <- eval t4
               _prim_int_print r'

    upto m n = (CInt m') <- eval m
               (CInt n') <- eval n
               b' <- _prim_int_gt m' n'
               if b' then
                pure (CNil)
               else
                m1' <- _prim_int_add m' 1
                m1 <- store (CInt m1')
                p <- store (Fupto m1 n)
                pure (CCons m p)

    sum l = l2 <- eval l
            case l2 of
              (CNil)       -> pure (CInt 0)
              (CCons x xs) -> (CInt x') <- eval x
                              (CInt s') <- sum xs
                              ax' <- _prim_int_add x' s'
                              pure (CInt ax')

    eval q = v <- fetch q
             case v of
              (CInt x'1)    -> pure v
              (CNil)        -> pure v
              (CCons y ys)  -> pure v
              (Fupto a b)   -> w <- upto a b
                               update q w
                               pure w
              (Fsum c)      -> z <- sum c
                               update q z
                               pure z
  |]