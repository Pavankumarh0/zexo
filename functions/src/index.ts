/**
 * Zexo Cloud Functions entry point. Each callable/trigger is re-exported here so
 * the Firebase CLI can discover it.
 */

export {
  getMe,
  updateMe,
  updateLocation,
  setVisibility,
  getUser,
  blockUser,
  deleteMe,
  registerPushToken,
} from "./users";

export { discoverNearby, discoverMap } from "./discover";

export {
  openThread,
  listThreads,
  expireThread,
  evaluateThreadExpiry,
} from "./threads";

export {
  createEvent,
  listEvents,
  getEvent,
  rsvpEvent,
  eventAttendees,
  addCohost,
  updateEvent,
} from "./events";

export {
  onUserCreate,
  purgeExpiredMessages,
  archiveEndedEvents,
  onMessageCreate,
} from "./triggers";
