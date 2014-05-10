{-# LANGUAGE ScopedTypeVariables #-}

-- | All the building blocks to allow rules to build events.
module Language.Nomyx.Events (
   Event(..),
   EventNumber,
   onEvent, onEvent_, onEventOnce,
   delEvent, delAllEvents,
   sendMessage, sendMessage_,
   onMessage, onMessageOnce,
   schedule, schedule_, schedule', schedule'_,
   getCurrentTime,
   oneWeek, oneDay, oneHour, oneMinute
   ) where

import Language.Nomyx.Expression
import Data.Typeable
import Control.Monad.State
import Data.List
import Data.Time hiding (getCurrentTime)
import Data.Time.Recurrence hiding (filter)
import Safe


-- * Events

-- | register a callback on an event
onEvent :: (Typeable e, Show e) => Event e -> ((EventNumber, e) -> Nomex ()) -> Nomex EventNumber
onEvent = OnEvent

-- | register a callback on an event, disregard the event number
onEvent_ :: forall e. (Typeable e, Show e) => Event e -> (e -> Nomex ()) -> Nomex EventNumber
onEvent_ e h = OnEvent e (\(_, d) -> h d)


-- | set an handler for an event that will be triggered only once
onEventOnce :: (Typeable e, Show e) => Event e -> (e -> Nomex ()) -> Nomex EventNumber
onEventOnce e h = do
    let handler (en, ed) = delEvent en >> h ed
    OnEvent e handler

delEvent :: EventNumber -> Nomex Bool
delEvent = DelEvent

delAllEvents :: (Typeable e) => Event e -> Nomex ()
delAllEvents = DelAllEvents

-- | broadcast a message that can be catched by another rule
sendMessage :: (Typeable a, Show a) => Msg a -> a -> Nomex ()
sendMessage = SendMessage

sendMessage_ :: String -> Nomex ()
sendMessage_ m = SendMessage (Msg m) ()

-- | subscribe on a message 
onMessage :: (Typeable m, Show m) => Msg m -> (m -> Nomex ()) -> Nomex EventNumber
onMessage name = onEvent_ (Message name)

onMessageOnce :: (Typeable m, Show m) => Msg m -> (m -> Nomex ()) -> Nomex EventNumber
onMessageOnce name = onEventOnce (Message name)

-- | on the provided schedule, the supplied function will be called
schedule :: Schedule Freq -> (UTCTime -> Nomex ()) -> Nomex ()
schedule sched f = do
    now <- liftEffect getCurrentTime
    let next = head $ starting now sched
    if next == now then executeAndScheduleNext f sched now
                   else void $ onEventOnce (Time next) $ executeAndScheduleNext f sched

executeAndScheduleNext :: (UTCTime -> Nomex ()) -> Schedule Freq -> UTCTime -> Nomex ()
executeAndScheduleNext f sched now = do
   f now
   let rest = drop 1 $ starting now sched
   when (rest /= []) $ void $ onEventOnce (Time $ head rest) $ executeAndScheduleNext f sched


schedule_ :: Schedule Freq -> Nomex () -> Nomex ()
schedule_ ts f = schedule ts (const f)

--at each time provided, the supplied function will be called
schedule' :: [UTCTime] -> (UTCTime -> Nomex ()) -> Nomex ()
schedule' sched f = do
    let sched' = sort sched
    now <- liftEffect getCurrentTime
    let nextMay = headMay $ filter (>=now) sched'
    case nextMay of
        Just next -> if next == now then executeAndScheduleNext' f sched' now
                                    else void $ onEventOnce (Time next) $ executeAndScheduleNext' f sched'
        Nothing -> return ()
            

executeAndScheduleNext' :: (UTCTime -> Nomex ()) -> [UTCTime] -> UTCTime -> Nomex ()
executeAndScheduleNext' f sched now = do
   f now
   let rest = drop 1 sched
   when (rest /= []) $ void $ onEventOnce (Time $ head rest) $ executeAndScheduleNext' f sched
   

schedule'_ :: [UTCTime] -> Nomex () -> Nomex ()
schedule'_ ts f = schedule' ts (const f)

getCurrentTime :: NomexNE UTCTime
getCurrentTime = CurrentTime

-- | duration
oneWeek, oneDay, oneHour, oneMinute :: NominalDiffTime
oneWeek = 7 * oneDay
oneDay = 24 * oneHour
oneHour = 60 * oneMinute
oneMinute = 60
