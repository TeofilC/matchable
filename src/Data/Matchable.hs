{-# LANGUAGE EmptyCase        #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TypeFamilies     #-}
{-# LANGUAGE TypeOperators    #-}
module Data.Matchable(
  -- * Matchable class
  Matchable(..),
  zipzipMatch,
  fmapRecovered,
  eqDefault,
  liftEqDefault,

  -- * Define Matchable by Generic
  Matchable'(), genericZipMatchWith,
) where

import           Control.Applicative

import           Data.Functor.Classes

import           Data.Maybe (fromMaybe, isJust)

import           Control.Comonad.Cofree
import           Control.Monad.Free
import           Data.Functor.Compose
import           Data.Functor.Identity
import           Data.List.NonEmpty     (NonEmpty)
import           Data.Map.Lazy          (Map)
import qualified Data.Map.Lazy          as Map

import           GHC.Generics

import           Data.Matchable.Orphans()

-- | Containers that allows exact structural matching of two containers.
class (Eq1 t, Functor t) => Matchable t where
  {- |
  Decides if two structures match exactly. If they match, return zipped version of them.

  > zipMatch ta tb = Just tab

  holds if and only if both of

  > ta = fmap fst tab
  > tb = fmap snd tab

  holds. Otherwise, @zipMatch ta tb = Nothing@.

  For example, the type signature of @zipMatch@ on the list Functor @[]@ reads as follows:

  > zipMatch :: [a] -> [b] -> Just [(a,b)]

  @zipMatch as bs@ returns @Just (zip as bs)@ if the lengths of two given lists are
  same, and returns @Nothing@ otherwise.

  ==== Example
  >>> zipMatch [1, 2, 3] ['a', 'b', 'c']
  Just [(1,'a'),(2,'b'),(3,'c')]
  >>> zipMatch [1, 2, 3] ['a', 'b']
  Nothing
  -}
  zipMatch :: t a -> t b -> Maybe (t (a,b))
  zipMatch = zipMatchWith (curry Just)

  {- |
  Match two structures. If they match, zip them with given function
  @(a -> b -> Maybe c)@. Passed function can make whole match fail
  by returning @Nothing@.

  A definition of 'zipMatchWith' must satisfy:

  * If there is a pair @(g, tab)@ such that fulfills all following three conditions,

    1. @ta = fmap fst tab@
    2. @tb = fmap snd tab@
    3. @fmap (uncurry f) tab = fmap (Just . g) tab@

    then @zipMatchWith f ta tb = Just (fmap g tab)@.

  * If there are no such pair, @zipMatchWith f ta tb = Nothing@.

  @zipMatch@ can be defined in terms of @zipMatchWith@.
  And if @t@ is also 'Traversable', @zipMatchWith@ can be defined in terms of @zipMatch@.
  When you implement both of them by hand, keep their relation in the way
  the default implementation is.

  > zipMatch             = zipMatchWith (curry pure)
  > zipMatchWith f ta tb = zipMatch ta tb >>= traverse (uncurry f)

  -}
  zipMatchWith :: (a -> b -> Maybe c) -> t a -> t b -> Maybe (t c)

  {-# MINIMAL zipMatchWith #-}

-- | > zipzipMatch = zipMatchWith zipMatch
zipzipMatch
  :: (Matchable t, Matchable u)
  => t (u a)
  -> t (u b)
  -> Maybe (t (u (a, b)))
zipzipMatch = zipMatchWith zipMatch

-- | @Matchable t@ implies @Functor t@.
--   It is not recommended to implement @fmap@ through this function,
--   so it is named @fmapRecovered@ but not @fmapDefault@.
fmapRecovered :: (Matchable t) => (a -> b) -> t a -> t b
fmapRecovered f ta =
  fromMaybe (error "Law-abiding Matchable instance") $
    zipMatchWith (\a _ -> Just (f a)) ta ta

-- | @Matchable t@ implies @Eq a => Eq (t a)@.
eqDefault :: (Matchable t, Eq a) => t a -> t a -> Bool
eqDefault = liftEqDefault (==)

-- | @Matchable t@ implies @Eq1 t@.
liftEqDefault :: (Matchable t) => (a -> b -> Bool) -> t a -> t b -> Bool
liftEqDefault eq tx ty =
  let u x y = if x `eq` y then Just () else Nothing
  in isJust $ zipMatchWith u tx ty

-----------------------------------------------

instance Matchable Identity where
  zipMatchWith = genericZipMatchWith

instance (Eq c) => Matchable (Const c) where
  zipMatchWith = genericZipMatchWith

instance Matchable Maybe where
  zipMatchWith = genericZipMatchWith

instance Matchable [] where
  zipMatchWith = genericZipMatchWith

instance Matchable NonEmpty where
  zipMatchWith = genericZipMatchWith

instance (Eq e) => Matchable ((,) e) where
  zipMatchWith = genericZipMatchWith

instance (Eq e) => Matchable (Either e) where
  zipMatchWith = genericZipMatchWith

instance (Eq k) => Matchable (Map k) where
  zipMatchWith u ma mb =
    Map.fromAscList <$> zipMatchWith (zipMatchWith u) (Map.toAscList ma) (Map.toAscList mb)

instance (Matchable f, Matchable g) => Matchable (Compose f g) where
  zipMatchWith = genericZipMatchWith

instance (Matchable f) => Matchable (Free f) where
  zipMatchWith u =
    let go (Free fma) (Free fmb) =
          Free <$> zipMatchWith go fma fmb
        go (Pure a) (Pure b) =
          Pure <$> u a b
        go _ _ = empty
    in go

instance (Matchable f) => Matchable (Cofree f) where
  zipMatchWith u =
    let go (a :< fwa) (b :< fwb) =
          liftA2 (:<) (u a b) (zipMatchWith go fwa fwb)
    in go

-- * Generic definition

{-|

An instance of Matchable can be implemened through GHC Generics.
You only need to do two things: Make your type Traversable and Generic1.

==== Example
>>> :set -XDeriveFoldable -XDeriveFunctor -XDeriveTraversable
>>> :set -XDeriveGeneric
>>> :{
  data MyTree label a = Leaf a | Node label [MyTree label a]
    deriving (Show, Read, Eq, Ord, Functor, Foldable, Traversable, Generic1)
:}

Then you can use @genericZipMatchWith@ to implement @zipMatchWith@ method.

>>> :{
  instance (Eq label) => Matchable (MyTree label) where
    zipMatchWith = genericZipMatchWith
  instance (Eq label) => Eq1 (MyTree label) where
    liftEq = liftEqDefault
  :}

>>> let example1 = zipMatch (Node "foo" [Leaf 1, Leaf 2]) (Node "foo" [Leaf 'a', Leaf 'b'])
>>> example1 :: Maybe (MyTree String (Int, Char))
Just (Node "foo" [Leaf (1,'a'),Leaf (2,'b')])
>>> let example2 = zipMatch (Node "foo" [Leaf 1, Leaf 2]) (Node "bar" [Leaf 'a', Leaf 'b'])
>>> example2 :: Maybe (MyTree String (Int, Char))
Nothing
>>> let example3 = zipMatch (Node "foo" [Leaf 1]) (Node "foo" [Node "bar" []])
>>> example3 :: Maybe (MyTree String (Int, Char))
Nothing

-}
class Matchable' t where
  zipMatchWith' :: (a -> b -> Maybe c) -> t a -> t b -> Maybe (t c)

-- | zipMatchWith via Generics.
genericZipMatchWith
  :: (Generic1 t, Matchable' (Rep1 t))
  => (a -> b -> Maybe c)
  -> t a
  -> t b
  -> Maybe (t c)
genericZipMatchWith u ta tb = to1 <$> zipMatchWith' u (from1 ta) (from1 tb)
{-# INLINABLE genericZipMatchWith #-}

instance Matchable' V1 where
  {-# INLINABLE zipMatchWith' #-}
  zipMatchWith' _ a _ = case a of { }

instance Matchable' U1 where
  {-# INLINABLE zipMatchWith' #-}
  zipMatchWith' _ _ _ = pure U1

instance Matchable' Par1 where
  {-# INLINABLE zipMatchWith' #-}
  zipMatchWith' u (Par1 a) (Par1 b) = Par1 <$> u a b

instance Matchable f => Matchable' (Rec1 f) where
  {-# INLINABLE zipMatchWith' #-}
  zipMatchWith' u (Rec1 fa) (Rec1 fb) = Rec1 <$> zipMatchWith u fa fb

instance (Eq c) => Matchable' (K1 i c) where
  {-# INLINABLE zipMatchWith' #-}
  zipMatchWith' _ (K1 ca) (K1 cb)
    = if ca == cb then pure (K1 ca) else empty

instance Matchable' f => Matchable' (M1 i c f) where
  {-# INLINABLE zipMatchWith' #-}
  zipMatchWith' u (M1 fa) (M1 fb) = M1 <$> zipMatchWith' u fa fb

instance (Matchable' f, Matchable' g) => Matchable' (f :+: g) where
  {-# INLINABLE zipMatchWith' #-}
  zipMatchWith' u (L1 fa) (L1 fb) = L1 <$> zipMatchWith' u fa fb
  zipMatchWith' u (R1 ga) (R1 gb) = R1 <$> zipMatchWith' u ga gb
  zipMatchWith' _ _       _       = empty

instance (Matchable' f, Matchable' g) => Matchable' (f :*: g) where
  {-# INLINABLE zipMatchWith' #-}
  zipMatchWith' u (fa :*: ga) (fb :*: gb) =
    liftA2 (:*:) (zipMatchWith' u fa fb) (zipMatchWith' u ga gb)

instance (Matchable f, Matchable' g) => Matchable' (f :.: g) where
  {-# INLINABLE zipMatchWith' #-}
  zipMatchWith' u (Comp1 fga) (Comp1 fgb) =
    Comp1 <$> zipMatchWith (zipMatchWith' u) fga fgb
