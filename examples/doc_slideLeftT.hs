#!/usr/bin/env stack
-- stack runghc --package reanimate
module Main(main) where

import Reanimate
import Reanimate.Builtin.Documentation
import Reanimate.Builtin.Slide
import Reanimate.Transition

main :: IO ()
main = reanimate $ docEnv $ signalT (curveS 2) slideLeftT left right
  where
    left = drawCircle
    right = staticFrame 1 (withFillOpacity 1 $ mkBackground "black") `parA`
            mapA (flipXAxis . withStrokeColor "white") drawCircle
