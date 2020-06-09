{-# LANGUAGE LambdaCase, TupleSections, BangPatterns, OverloadedStrings #-}
{-# LANGUAGE Strict #-}
module Reducer.ExtendedSyntax.IO (reduceFun) where

import Debug.Trace

import Control.Monad.RWS.Strict hiding (Alt)

import Data.Foldable (fold)
import Data.Map (Map)
import qualified Data.Map as Map
import Data.Vector.Mutable as Vector
import Data.IORef

import Reducer.ExtendedSyntax.Base
import Reducer.ExtendedSyntax.PrimOps
import Grin.ExtendedSyntax.Grin

-- models computer memory
data IOStore = IOStore
  { sVector :: IOVector RTVal
  , sLast   :: IORef Int
  }

emptyStore1 :: IO IOStore
emptyStore1 = IOStore <$> new (10 * 1024 * 1024) <*> newIORef 0

type Prog = Map Name Def
type GrinS a = RWST Prog () IOStore IO a

getProg :: GrinS Prog
getProg = reader id

getStore :: GrinS IOStore
getStore = get

-- TODO: Resize
insertStore :: RTVal -> GrinS Int
insertStore x = do
  (IOStore v l) <- getStore
  lift $ do
    n <- readIORef l
    Vector.write v n x
    writeIORef l (n + 1)
    pure n

lookupStore :: Int -> GrinS RTVal
lookupStore n = do
  (IOStore v _) <- getStore
  lift $ do
    Vector.read v n

updateStore :: Int -> RTVal -> GrinS ()
updateStore n x = do
  (IOStore v _) <- getStore
  lift $ do
    Vector.write v n x

pprint exp = trace (f exp) exp where
  f = \case
    EBind  a b _ -> unwords ["Bind", "{",show a,"} to {", show b, "}"]
    ECase  a _ -> unwords ["Case", show a]
    SBlock {} -> "Block"
    a -> show a


evalExp :: [External] -> Env -> Exp -> GrinS RTVal
evalExp exts env exp = case {-pprint-} exp of
  EBind op pat exp -> evalSimpleExp exts env op >>= \v -> evalExp exts (bindPat env v pat) exp
  -- TODO:
  ECase scrut alts ->
    let defaultAlts = [exp | Alt DefaultPat _ exp <- alts]
        defaultAlt  = if Prelude.length defaultAlts > 1
                        then error "multiple default case alternative"
                        else Prelude.take 1 defaultAlts

        altNames      = [ name | Alt _ name _ <- alts ]
        scrutVal      = evalVar env scrut
        boundAltNames = fold $ map (`Map.singleton` scrutVal) altNames
        env'          = boundAltNames <> env
    in case evalVar env scrut of
      RT_ConstTagNode t l ->
        let (vars,exp) = head $ [(b,exp) | Alt (NodePat a b) _ exp <- alts, a == t] ++ map ([],) defaultAlt ++ error ("evalExp - missing Case Node alternative for: " ++ show t)
            go a [] [] = a
            go a (x:xs) (y:ys) = go (Map.insert x y a) xs ys
            go _ x y = error $ "invalid pattern and constructor: " ++ show (t,x,y)
        in  evalExp exts (go env' vars l) exp
      RT_Lit l    -> evalExp exts env' $ head $ [exp | Alt (LitPat a) _ exp <- alts, a == l] ++ defaultAlt ++ error ("evalExp - missing Case Lit alternative for: " ++ show l)
      x -> error $ "evalExp - invalid Case dispatch value: " ++ show x
  exp -> evalSimpleExp exts env exp

evalSimpleExp :: [External] -> Env -> SimpleExp -> GrinS RTVal
evalSimpleExp exts env = \case
  SApp n a -> do
              let args = map (evalVar env) a
                  go a [] [] = a
                  go a (x:xs) (y:ys) = go (Map.insert x y a) xs ys
                  go _ x y = error $ "invalid pattern for function: " ++ show (n,x,y)
              if isExternalName exts n
                then evalPrimOp n [] args
                else do
                  Def _ vars body <- (Map.findWithDefault (error $ "unknown function: " ++ unpackName n) n) <$> getProg
                  evalExp exts (go env vars args) body
  SReturn v -> pure $ evalVal env v
  SStore v -> do
              let v' = evalVar env v
              l <- insertStore v'
              -- modify' (\(StoreMap m s) -> StoreMap (IntMap.insert l v' m) (s+1))
              pure $ RT_Loc l
  SFetch ptr -> case evalVar env ptr of
              RT_Loc l -> lookupStore l
              x -> error $ "evalSimpleExp - Fetch expected location, got: " ++ show x
--  | FetchI  Name Int -- fetch node component
  SUpdate ptr var -> do
              let v' = evalVar env var
              case evalVar env ptr of
                RT_Loc l -> updateStore l v' >> pure v'
                x -> error $ "evalSimpleExp - Update expected location, got: " ++ show x
  SBlock a -> evalExp exts env a
  x -> error $ "evalSimpleExp: " ++ show x

reduceFun :: Program -> Name -> IO RTVal
reduceFun (Program exts l) n = do
  store <- emptyStore1
  (val, _, _) <- runRWST (evalExp exts mempty e) m store
  pure val
  where
    m = Map.fromList [(n,d) | d@(Def n _ _) <- l]
    e = case Map.lookup n m of
          Nothing -> error $ "missing function: " ++ unpackName n
          Just (Def _ [] a) -> a
          _ -> error $ "function " ++ unpackName n ++ " has arguments"
