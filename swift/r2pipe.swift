import Foundation
#if HAVE_SPAWN
//import r2PipeSpawn
#endif
#if USE_SWIFTY_JSON
import SwiftyJSON
#endif

enum R2PipeChannel {
	case Unknown
	case Http
	case Spawn
	case Env
}

extension String {
	func URLEncodedString() -> String? {
		let customAllowedSet = NSCharacterSet.URLQueryAllowedCharacterSet()
		let escapedString = self.stringByAddingPercentEncodingWithAllowedCharacters(customAllowedSet)
		return escapedString
	}
	func ToR2WebURL(str:String) -> String {
		var ret = self;
		if !self.hasSuffix ("/") {
			ret += "/";
		}
		return ret + str.URLEncodedString()!;
	}
}

class R2Pipe {
	var mode : R2PipeChannel = .Unknown;
	var path = "";
#if HAVE_SPAWN
	var r2pipeSpawn : R2PipeSpawn? = nil;
#endif
#if USE_ENV_PIPE
	var r2pipeEnv : R2PipeEnv? = nil;
#endif

	init?(url: String) {
		if url == "#!pipe" {
#if USE_ENV_PIPE
			mode = .Env
			self.r2pipeEnv = R2PipeEnv();
			if self.r2pipeEnv == nil {
				return nil;
			}
#else
			return nil;
#endif
		} else if url.rangeOfString("://") != nil {
			if url.hasPrefix ("http://")
			|| url.hasPrefix ("https://") {
				mode = .Http
				path = url
			}
		} else {
#if HAVE_SPAWN
			mode = .Spawn
			path = url
			self.r2pipeSpawn = R2PipeSpawn(file:url)
#else
			return nil
#endif
		}
	}

	func cmdHttp(str: String, closure:(String)->()) -> Bool {
		let urlstr = self.path.ToR2WebURL(str);
		let url = NSURL(string: urlstr);
		let request = NSURLRequest(URL: url!)
#if USE_NSURL_SESSION
		NSURLSession.sharedSession().dataTaskWithRequest(request, completionHandler:{
			(data:NSData?, url:NSURLResponse?, error:NSError?) -> Void in
			let str = NSString(data: data!, encoding: NSUTF8StringEncoding)
			closure (str as! String);
		})
#else
		NSURLConnection.sendAsynchronousRequest(request, queue: NSOperationQueue.mainQueue()) {(response, data, error) in
			let str = NSString(data: data!, encoding: NSUTF8StringEncoding)
			closure (str as! String);
		}
#endif
		return true;
	}

	func cmdHttpSync(str: String) -> String? {
#if USE_NSURL_SESSION
		/* not yet supported */
#endif
		let urlstr = self.path.ToR2WebURL(str);
		let url = NSURL(string: urlstr);
		let request = NSURLRequest(URL: url!)
		let response:AutoreleasingUnsafeMutablePointer<NSURLResponse?> = nil;
		do {
			let responseData = try NSURLConnection.sendSynchronousRequest(
					request, returningResponse: response) as NSData;
			let responseStr = NSString(data:responseData, encoding:NSUTF8StringEncoding);
			if responseStr != nil {
				return responseStr! as String;
			}
		} catch _ {
			print ("catch");
		}
		return nil;
	}

	func cmd(str:String, closure:(String)->()) -> Bool {
		switch (mode) {
		case .Http:
			return cmdHttp(str, closure:closure);
		case .Spawn:
			if let r2p = self.r2pipeSpawn {
				return r2p.sendCommand (str, closure:closure);
			} else {
				return false;
			}
		case .Env:
			if let r2p = self.r2pipeEnv {
				return r2p.sendCommand (str, closure:closure);
			} else {
				return false;
			}
		default:
			return false;
		}
	}

	func cmdSync(str:String) -> String? {
		switch (mode) {
		case .Http:
			return cmdHttpSync(str);
		case .Spawn:
			if let r2p = self.r2pipeSpawn {
				return r2p.sendCommandSync(str);
			} else {
				return nil;
			}
		case .Env:
			if let r2p = self.r2pipeEnv {
				return r2p.sendCommandSync(str);
			} else {
				return nil;
			}
		default:
			return nil;
		}
	}

	/* JSON APIs */
#if USE_SWIFTY_JSON
	func cmdjSync(str:String) -> NSDictionary? {
		if let s = cmdSync (str) {
			return JSON (s)
		}
		return nil;
	}

	func cmdj(str:String, closure:(NSDictionary)->()) -> Bool {
		cmd (str, closure:{
			(s:String)->() in
			if let js = JSON (obj) {
				closure (js)
			}
		});
		return true;
	}
#else
	func jsonParse(str:String) -> NSDictionary? {
		if let data = str.dataUsingEncoding(NSUTF8StringEncoding) {
			do {
				if let parsedObject: AnyObject? = try NSJSONSerialization.JSONObjectWithData(data,
						options: NSJSONReadingOptions.AllowFragments) {
					return parsedObject as? NSDictionary
				}
			} catch _ {
				return nil;
			}
		}
		return nil;
	}

	func cmdjSync(str:String) -> NSDictionary? {
		if let s = cmdSync (str) {
			if let obj = self.jsonParse (s) {
				return obj;
			}
		}
		return nil;
	}

	func cmdj(str:String, closure:(NSDictionary)->()) -> Bool {
		cmd (str, closure:{
			(s:String)->() in
			if let obj = self.jsonParse (s) {
				closure (obj);
			}
		});
		return true;
	}
#endif
}