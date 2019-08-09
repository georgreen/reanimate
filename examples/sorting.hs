#!/usr/bin/env stack
-- stack --resolver lts-13.14 runghc --package reanimate
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
module Main (main) where

import           Control.Lens

import           Graphics.SvgTree (Number(..))
import           Reanimate.Driver (reanimate)
import           Reanimate.LaTeX
import           Reanimate.Monad
import           Reanimate.Svg
import           Reanimate.Signal
import           Reanimate.Raster
import           Codec.Picture
import           Data.Text (Text)
import           Data.Colour.RGBSpace.HSV
import           Data.Colour.RGBSpace

import Control.Monad.ST
import Control.Monad.State.Strict
import Data.Vector.Unboxed (Vector)
import qualified Data.Vector.Unboxed as V
import qualified Data.Vector.Generic.Mutable as GV
import System.Random.Shuffle
import System.Random
import Debug.Trace

main :: IO ()
main = reanimate $
  demonstrateAlgorithm "Bubble sort" bubbleSort `before`
  demonstrateAlgorithm "Merge sort (left leaning)" mergeSort `before`
  demonstrateAlgorithm "Merge sort" mergeSortUp `before`
  demonstrateAlgorithm "Insertion sort" insertSort `before`
  demonstrateAlgorithm "Selection sort" selectionSort `before`
  adjustSpeed (1/3) (demonstrateAlgorithm "Quicksort" quicksort)

demonstrateAlgorithm :: Text -> (forall s. S s ()) -> Animation
demonstrateAlgorithm name algo = mkAnimation 5 $ do
    s <- getSignal signalLinear
    let img = generateImage pixelRenderer width height
        seed = round (s * 3000)
        pixelRenderer x y = PixelRGB8 (round $ r*255) (round $ g*255) (round $ b*255)
          where
            num = (sortedDat !! y) V.! x
            RGB r g b = hsv (fromIntegral num / 255 * 360) 0.7 1
        sortedDat = runSort' seed algo width
        width = 1024
        height = length sortedDat
    emit $ mkGroup
      [ mkBackground "black"

      , translate 0 (10) $ center $ scaleToSize 150 150 $ embedImage img
      , translate 0 (-75) $ withFillColor "white" $ scale 1.5 $ center $
        latex name
      , withFillColor "white" $ translate (-85) 10 $ rotate 90 $ center $
        latex "$Time \\rightarrow$"
      , withFillColor "white" $ translate (90) 10 $
        mkCircle (Num 0, Num 0) (Num $ (1-s)*10)
      ]
  where


-- main :: IO ()
-- main = print $ length $ runSort bubbleSort 2560

-- [3,4,1,2]
-- [

-- [1,2,3,4]
-- 0 3
-- half: 0 + 3`div`2 = 1
-- mergeSort 0 (0+1)
-- mergeSort (0+1) 3

data Env s = Env
  { envHistory :: [Vector Int]
  , envState :: V.MVector s Int }

type S s a = StateT (Env s) (ST s) a

runSort :: (forall s. S s ()) -> Int -> [Vector Int]
runSort = runSort' 0xDEADBEEF

runSort' :: Int -> (forall s. S s ()) -> Int -> [Vector Int]
runSort' seed sortFn len = reverse $ runST (do
    arr <- V.thaw (V.fromList lst)
    let env = Env [] arr
    envHistory <$> execStateT sortFn env)
  where
    lst = shuffle' [1 .. len] len (mkStdGen seed)
    skipDups (x:y:xs) | x == y = skipDups (x:xs)
    skipDups (x:xs) = x : skipDups xs
    skipDups [] = []

readS :: Int -> S s Int
readS idx = do
  arr <- gets envState
  GV.unsafeRead arr idx

writeS :: Int -> Int -> S s ()
writeS idx val = do
  arr <- gets envState
  GV.unsafeWrite arr idx val

swapS :: Int -> Int -> S s ()
swapS a b = do
  arr <- gets envState
  GV.unsafeSwap arr a b

inputLength :: S s Int
inputLength = GV.length <$> gets envState

snapshot :: S s ()
snapshot = do
  arr <- gets envState
  vec <- V.freeze arr
  modify $ \st -> st { envHistory = vec : envHistory st }

mergeSort :: S s ()
mergeSort = do
  snapshot
  len <- inputLength
  mergeSort' 0 (len-1)

mergeSort' :: Int -> Int -> S s ()
mergeSort' start end | start == end = return ()
mergeSort' start end = do
  let half = start + (end-start) `div` 2
  mergeSort' start half
  mergeSort' (half+1) end
  leftVals <- mapM readS [start .. half]
  rightVals <- mapM readS [half+1 .. end]
  zipWithM_ writeS [start..] (merge leftVals rightVals)
  snapshot

merge [] xs = xs
merge xs [] = xs
merge (x:xs) (y:ys)
  | x < y     = x : merge xs (y:ys)
  | otherwise = y : merge (x:xs) ys


mergeSortUp :: S s ()
mergeSortUp = do
  snapshot
  len <- inputLength
  let chunkSizes = takeWhile (< len) $ map (2^) [0..]
  forM_ chunkSizes $ bottomUpMergeSort'

bottomUpMergeSort' :: Int -> S s ()
bottomUpMergeSort' chunkSize = do
  len <- inputLength
  forM_ [0, chunkSize*2 .. len-1] $ \idx -> do
    leftVals <- mapM readS (take chunkSize [idx .. len-1])
    rightVals <- mapM readS (take chunkSize (drop chunkSize [idx .. len-1]))
    zipWithM_ writeS [idx..] (merge leftVals rightVals)
    snapshot

selectionSort :: S s ()
selectionSort = do
  snapshot
  len <- inputLength
  forM_ [0 .. len-1] $ \j -> do
    jVal <- readS j
    i <- findMin j (j+1) len
    swapS j i
    snapshot
  where
    findMin j i len | i >= len = return j
    findMin j i len = do
      jVal <- readS j
      iVal <- readS i
      if iVal < jVal
        then findMin i (i+1) len
        else findMin j (i+1) len

insertSort :: S s ()
insertSort = do
  snapshot
  len <- inputLength
  forM_ [1 .. len-1] $ \j -> do
    a <- readS j
    worker a j
    snapshot
  where
    worker a 0 = writeS 0 a
    worker a j = do
      b <- readS (j-1)
      if (a < b)
        then do
          writeS j b
          worker a (j-1)
        else
          writeS j a


bubbleSort :: S s ()
bubbleSort = do
  worker True 0
  where
    worker True 0 = do
      snapshot
      len <- inputLength
      worker False (len-1)
    worker False 0 = snapshot
    worker changed n = do
      a <- readS n
      b <- readS (n-1)
      if a < b
        then do
          writeS n b
          writeS (n-1) a
          when (n `mod` 50 == 0) snapshot
          worker True (n-1)
        else worker changed (n-1)

quicksort :: S s ()
quicksort = do
    snapshot
    len <- inputLength
    worker [(0, len-1)]
  where
    worker :: [(Int,Int)] -> S s ()
    worker [] = return ()
    worker ((lo,hi):rest) = do
      pivot <- readS (lo + (hi-lo) `div` 2)
      p <- partition pivot lo hi
      snapshot
      worker $ insertWork (lo, p) $ insertWork (p+1, hi) $ rest

    partition pivot lo hi = do
      loVal <- readS lo
      hiVal <- readS hi
      if loVal < pivot
        then partition pivot (lo+1) hi
        else if hiVal > pivot
          then partition pivot lo (hi-1)
          else if lo >= hi
            then return hi
            else do
              writeS lo hiVal
              writeS hi loVal
              snapshot
              partition pivot (lo+1) (hi-1)

    insertWork :: (Int,Int) -> [(Int,Int)] -> [(Int,Int)]
    insertWork (lo, hi) rest | lo >= hi = rest
    insertWork (lo, hi) [] = [(lo, hi)]
    insertWork (lo, hi) ((lo', hi'):rest)
      | hi-lo > hi'-lo' = (lo,hi) : (lo', hi') : rest
      | otherwise       = (lo', hi') : insertWork (lo, hi) rest