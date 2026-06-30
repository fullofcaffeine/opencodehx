package opencodehx.storage;

import opencodehx.session.MessageID;
import opencodehx.session.MessageTypes.Info;
import opencodehx.session.MessageTypes.Part;
import opencodehx.session.MessageTypes.WithParts;
import opencodehx.session.PartID;
import opencodehx.session.SessionID;
import opencodehx.session.SessionInfo.ProjectInfo;
import opencodehx.session.SessionInfo.SessionInfo;

typedef MessagePage = {
	final items:Array<WithParts>;
	final more:Bool;
	@:optional final cursor:String;
}

interface SessionStore {
	function close():Void;
	function upsertProject(project:ProjectInfo):Void;
	function migrateGlobalSessions(worktree:String, projectID:String):Int;
	function createSession(info:SessionInfo):Void;
	function getSession(id:SessionID):SessionInfo;
	function listSessions(limit:Int):Array<SessionInfo>;
	function updateSession(info:SessionInfo):Void;
	function deleteSession(id:SessionID):Void;
	function upsertMessage(info:Info):Void;
	function getMessage(sessionID:SessionID, messageID:MessageID):WithParts;
	function removeMessage(sessionID:SessionID, messageID:MessageID):Void;
	function upsertPart(part:Part, time:Float):Void;
	function removePart(sessionID:SessionID, messageID:MessageID, partID:PartID):Void;
	function getPart(sessionID:SessionID, messageID:MessageID, partID:PartID):Null<Part>;
	function pageMessages(sessionID:SessionID, limit:Int, ?before:String):MessagePage;
}
