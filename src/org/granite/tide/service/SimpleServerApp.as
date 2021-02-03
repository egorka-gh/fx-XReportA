/*
 *   GRANITE DATA SERVICES
 *   Copyright (C) 2006-2014 GRANITE DATA SERVICES S.A.S.
 *
 *   This file is part of the Granite Data Services Platform.
 *
 *                               ***
 *
 *   Community License: GPL 3.0
 *
 *   This file is free software: you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published
 *   by the Free Software Foundation, either version 3 of the License,
 *   or (at your option) any later version.
 *
 *   This file is distributed in the hope that it will be useful, but
 *   WITHOUT ANY WARRANTY; without even the implied warranty of
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 *   GNU General Public License for more details.
 *
 *   You should have received a copy of the GNU General Public License
 *   along with this program. If not, see <http://www.gnu.org/licenses/>.
 *
 *                               ***
 *
 *   Available Commercial License: GraniteDS SLA 1.0
 *
 *   This is the appropriate option if you are creating proprietary
 *   applications and you are not prepared to distribute and share the
 *   source code of your application under the GPL v3 license.
 *
 *   Please visit http://www.granitedataservices.com/license for more
 *   details.
 */
package org.granite.tide.service {

    import mx.logging.ILogger;
    import mx.logging.Log;
    import mx.messaging.Channel;
    import mx.messaging.ChannelSet;
    import mx.messaging.channels.AMFChannel;
    import mx.messaging.channels.SecureAMFChannel;
    import mx.rpc.remoting.RemoteObject;

    import org.granite.gravity.Consumer;
    import org.granite.gravity.Producer;
    import org.granite.gravity.channels.GravityChannel;
    import org.granite.gravity.channels.SecureGravityChannel;
    import org.granite.tide.Tide;

    /**
     * 	@author William DRAI
     */
    public class SimpleServerApp implements IServerApp {
        
        private static var log:ILogger = Log.getLogger("org.granite.tide.service.SimpleServerApp");

        private static const DEFAULT_CONTEXT_ROOT:String = "{context.root}";
        private static const DEFAULT_SERVER_NAME:String = "{server.name}";
        private static const DEFAULT_SERVER_PORT:String = "{server.port}";

        private var _contextRoot:String = DEFAULT_CONTEXT_ROOT;
		private var _secure:Boolean = false;
        private var _serverName:String = DEFAULT_SERVER_NAME;
        private var _serverPort:String = DEFAULT_SERVER_PORT;


		/**
		 * 	Tide constructor used at component instantiation
		 *
		 * 	@param name component name
		 *  @param context current context
		 */
        public function SimpleServerApp(contextRoot:String = DEFAULT_CONTEXT_ROOT, secure:Boolean = false, serverName:String = DEFAULT_SERVER_NAME, serverPort:String = DEFAULT_SERVER_PORT) {
            _secure = secure;
            _serverName = serverName;
            _serverPort = serverPort;
            _contextRoot = contextRoot;
        }

        public function get secure():Boolean {
            return _secure;
        }

        public function set secure(value:Boolean):void {
            _secure = value;
        }

        public function get serverName():String {
            return _serverName;
        }

        public function set serverName(value:String):void {
            _serverName = value;
        }

        public function get serverPort():String {
            return _serverPort;
        }

        public function set serverPort(value:String):void {
            _serverPort = value;
        }

        public function get contextRoot():String {
            return _contextRoot;
        }

        public function set contextRoot(value:String):void {
            _contextRoot = value;
        }
        
        public function initialize():void {
            var application:Object = Tide.currentApplication();

            if (application.url && application.url.indexOf("http") == 0)
            	parseUrl(application.url);
        }
        
        public function parseUrl(url:String):void {
			if (url.indexOf("https") == 0)
				_secure = true;
			
            var idx0:int = url.indexOf("://");
            if (idx0 > 0) {
                var idx:int = url.indexOf("/", idx0+3);
                if (idx > 0) {
                    var idx1:int = url.indexOf(":", idx0+3);
                    if (idx1 > 0) {
                        if (serverName == null || serverName == DEFAULT_SERVER_NAME)
                            serverName = url.substring(idx0+3, idx1);
                        if (serverPort == null || serverPort == DEFAULT_SERVER_PORT)
                            serverPort = url.substring(idx1+1, idx);
                    }
                    else {
                        if (serverName == null || serverName == DEFAULT_SERVER_NAME)
                            serverName = url.substring(idx0+3, idx);
                        if (serverPort == null || serverPort == DEFAULT_SERVER_PORT)
                            serverPort = secure ? "443" : "80";
                    }
                    var idx2:int = url.indexOf("/", idx+1);
                    if ((contextRoot == null || contextRoot == DEFAULT_CONTEXT_ROOT)) {
						if (idx2 > idx)
							contextRoot = url.substring(idx, idx2);
						else if (idx2 < 0)
							contextRoot = "";
					}
                }
            }
        }
    }
}
