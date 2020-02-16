{-# LANGUAGE QuasiQuotes #-}
module Reducer.ExtendedSyntax.IOSpec where

import Reducer.ExtendedSyntax.Base
import Reducer.ExtendedSyntax.IO

import Data.Text
import qualified Data.Map as Map

import Test.Hspec

import Grin.ExtendedSyntax.TH
import Grin.ExtendedSyntax.Syntax
import Grin.ExtendedSyntax.PrimOpsPrelude

runTests :: IO ()
runTests = hspec spec

-- TODO: We could implement a parametric reducer test suite.
-- It would reduce the GRIN program with a user-supplied function.

spec :: Spec
spec = do
  describe "Pure reducer" $ do

    describe "some primops" $ do
      it "int add & int gt" $ do
        let program = withPrimPrelude [prog|
          grinMain =
            n <- pure 2
            m <- pure 5
            k <- _prim_int_add m n
            b <- _prim_int_gt m n
            case b of
              #True  @ alt1 -> pure k
              #False @ alt2 -> pure 0
        |]
        reduceFun program "grinMain" `shouldReturn` RT_Lit (LInt64 7)

    describe "as-patterns" $ do
      it "pure" $ do
        let program = withPrimPrelude [prog|
          grinMain =
            k0 <- pure 0
            v0 <- pure (CInt k0)
            (CInt k1) @ v1 <- pure v0
            (CInt k2) @ _1 <- pure v1
            pure k2
        |]
        reduceFun program "grinMain" `shouldReturn` RT_Lit (LInt64 0)

      it "fetch" $ do
        let program = withPrimPrelude [prog|
          grinMain =
            k0 <- pure 0
            v0 <- pure (CInt k0)
            p0 <- store v0
            (CInt k1) @ v1 <- fetch p0
            (CInt k2) @ _1 <- pure v1
            pure k2
        |]
        reduceFun program "grinMain" `shouldReturn` RT_Lit (LInt64 0)

    describe "case expressions" $ do
      it "literal scrutinee" $ do
        let program = [prog|
          grinMain =
            n <- pure #True
            case n of
              #True  @ alt1 -> pure alt1
              #False @ alt2 -> pure alt2
        |]
        reduceFun program "grinMain" `shouldReturn` RT_Lit (LBool True)

      it "node scrutinee" $ do
        let program = [prog|
          grinMain =
            n <- pure (COne)
            case n of
              (COne)   @ alt1 -> pure 1
              #default @ alt2 -> pure 0
        |]
        reduceFun program "grinMain" `shouldReturn` RT_Lit (LInt64 1)

    describe "scoping" $ do
      it "multiple independent calls" $ do
        let program = [prog|
          grinMain =
            one <- pure 1
            two <- pure 2
            n1  <- pure (CInt one)
            n2  <- pure (CInt two)
            _1 <- foo n1
            foo n2

          foo x =
            (CInt k) @ _2 <- pure x
            pure k
        |]
        reduceFun program "grinMain" `shouldReturn` RT_Lit (LInt64 2)

      it "recursive calls" $ do
        let program = [prog|
          grinMain =
            true <- pure #True
            one  <- pure 1
            n1   <- pure (CInt one)
            foo true n1

          foo b x =
            (CInt k) @ _2 <- pure x
            case b of
              #True @ alt1 ->
                false <- pure #False
                two   <- pure 2
                n2    <- pure (CInt two)
                foo false n2
              #False @ alt2 ->
                pure k
        |]
        reduceFun program "grinMain" `shouldReturn` RT_Lit (LInt64 2)

    describe "complex" $ do

      it "sum_simple" $ do
        reduceFun sumSimple "grinMain" `shouldReturn` RT_Lit (LInt64 50005000)

sumSimple :: Exp
sumSimple = withPrimPrelude [prog|
  grinMain =
    y.0 <- pure 1
    v.0 <- pure (CInt y.0)
    t1  <- store v.0
    y.1 <- pure 10000
    v.1 <- pure (CInt y.1)
    t2  <- store v.1
    v.2 <- pure (Fupto t1 t2)
    t3  <- store v.2
    v.3 <- pure (Fsum t3)
    t4  <- store v.3
    (CInt r') @ p.0 <- eval $ t4
    pure r'

  grinMain2 =
    c.1 <- pure 1
    c.2 <- pure 3
    c.3 <- pure 0
    j.1 <- pure (CInt c.1)
    j.2 <- pure (CInt c.2)
    j.3 <- pure (CInt c.3)
    g.1 <- store j.1
    g.2 <- store j.2
    g.3 <- store j.3

    k.0 <- pure (CNil)
    t.0 <- store k.0
    k.1 <- pure (CCons g.1 t.0)
    t.1 <- store k.1
    k.2 <- pure (CCons g.2 t.1)
    t.2 <- store k.2
    k.3 <- pure (CCons g.3 t.2)
    t.3 <- store k.3

    w.1 <- pure (Fsum t.2)
    t.4 <- store w.1
    r.1 <- eval t.4
    pure r.1

  upto m n =
    (CInt m') @ p.2 <- eval $ m
    (CInt n') @ p.1 <- eval $ n
    b' <- _prim_int_gt $ m' n'
    case b' of
      #True @ alt.0 ->
        v.4 <- pure (CNil)
        pure v.4
      #False @ alt.1 ->
        x.7 <- pure 1
        m1' <- _prim_int_add $ m' x.7
        v.5 <- pure (CInt m1')
        m1  <- store v.5
        v.6 <- pure (Fupto m1 n)
        p   <- store v.6
        v.7 <- pure (CCons m p)
        pure v.7

  sum l =
    l2 <- eval $ l
    case l2 of
      (CNil) @ alt.2 ->
        y.10 <- pure 0
        v.8  <- pure (CInt y.10)
        pure v.8
      (CCons x xs) @ alt.3 ->
        (CInt x') @ p.4 <- eval $ x
        (CInt s') @ p.3 <- sum $ xs
        ax' <- _prim_int_add $ x' s'
        v.9 <- pure (CInt ax')
        pure v.9

  eval q =
    v <- fetch q
    case v of
      (CInt x'1) @ alt.4 ->
        pure v
      (CNil) @ alt.5 ->
        pure v
      (CCons y ys) @ alt.6 ->
        pure v
      (Fupto a b) @ alt.7 ->
        w <- upto $ a b
        p.5 <- update q w
        pure w
      (Fsum c) @ alt.8 ->
        z <- sum $ c
        p.6 <- update q z
        pure z
  |]
