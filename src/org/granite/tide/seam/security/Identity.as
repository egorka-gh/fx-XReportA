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
package org.granite.tide.seam.security {

    import flash.utils.flash_proxy;
    import flash.utils.Dictionary;
    import flash.events.Event;
    
    import mx.utils.object_proxy;
    
    import org.granite.tide.Tide;
    import org.granite.tide.BaseContext;
    import org.granite.tide.Component;
    import org.granite.tide.IIdentity;
    import org.granite.tide.events.TideContextEvent;
    import org.granite.tide.events.TideResultEvent;
    import org.granite.tide.events.TideFaultEvent;
    import org.granite.tide.seam.Seam;
    import org.granite.tide.service.ServerSession;

    use namespace flash_proxy;
    use namespace object_proxy;
    

    [Bindable]
    /**
     * 	Implementation of the identity component for Seam services.<br/>
     *  Integrates with the server-side identity component of Seam.<br/>
     *  <br/>
     *  The basic way of using it is by populating username/password and calling login :<br/>
     *  <pre>
     *  identity.username = 'john';
     *  identity.password = 'doe';
     *  identity.login();
     *  </pre>
     * 
     * 	@author William DRAI
     */
    public class Identity extends Component implements IIdentity {

        public function Identity(serverSession:ServerSession = null):void {
            super(serverSession);
        }

        public override function meta_init(componentName:String, context:BaseContext):void {
            super.meta_init(componentName, context);
            context.addContextEventListener(Tide.LOGIN, loginSuccessHandler);
        }

        
        /**
         * 	User name
         */
        public function get username():String {
            return super.getProperty("username") as String;
        }
        /**
         * 	User name
         */
        public function set username(username:String):void {
            super.setProperty("username", username);
        }
        
        /**
         * 	Password
         */
        public function set password(password:String):void {
            super.setProperty("password", password);
        }
        
        /**
         * 	Logged in
         */
        public function get loggedIn():Boolean {
            return super.getProperty("loggedIn");
        }
        /**
         * 	Logged in
         */
        public function set loggedIn(loggedIn:Boolean):void {
            setInternalProperty("loggedIn", loggedIn);
            if (!loggedIn)
				_context.meta_logout(_serverSession, this);
        }
        
        
        /**
         * 	Triggers a remote call to check is user is currently logged in
         *  Can be used at application startup to handle browser refresh cases
         * 
         *  @param resultHandler optional result handler
         *  @param faultHandler optional fault handler 
         */
        public function isLoggedIn(resultHandler:Function = null, faultHandler:Function = null):void {
            var l:Boolean = loggedIn;
            var u:String = username;
            
            _context.meta_isLoggedIn(_serverSession, this, resultHandler, faultHandler);
        }
        
        /**
         *	Triggers a login request
         * 
         *  @param resultHandler optional result handler
         *  @param faultHandler optional fault handler 
         */  
        public function login(resultHandler:Function = null, faultHandler:Function = null, charset:String = null):void {
            var l:Boolean = loggedIn;    // Force evaluation of loggedIn state
            
            _context.meta_login(_serverSession, this, object.username, object.password, resultHandler, faultHandler, charset);
        }
        
        private function loginSuccessHandler(event:TideContextEvent):void {
            initSecurityCache();
        }
        
        
        /**
         *	Triggers a logout request
         */  
        public function logout():void {
            loggedIn = false;
			username = null;
            
            clearSecurityCache();
            
            // Must be at the end, because it resets the current identity instance
            // Not necessary, called by loggedIn = false
            // _context.meta_logout(this);
        }
        
        
        private var _rolesCache:Object = new Object();
        
        /**
         *	Check role permission for the specified role
         *  
         *  @param roleName role name
         *  @param resultHandler result handler
         *  @param faultHandler fault handler
         *  @return true is role allowed
         */ 
        [Bindable("roleChanged")]
        public function hasRole(roleName:String, resultHandler:Function = null, faultHandler:Function = null):Boolean {
            var has:* = _rolesCache[roleName];
            if (has === undefined) {
                if (loggedIn) {
                    var responder:TideRoleResponder = new TideRoleResponder(roleResultHandler, roleFaultHandler, roleName);
                    responder.addHandlers(resultHandler, faultHandler);
                    _context.meta_callComponent(_serverSession, this, "hasRole", [roleName, responder], false);
                    _rolesCache[roleName] = responder;
                }
                return false;
            }
            if (has is TideRoleResponder) {
            	has.addHandlers(resultHandler, faultHandler);
            	return false;
            }
            if (resultHandler != null) {
                var event:TideResultEvent = new TideResultEvent(TideResultEvent.RESULT, _context, false, false, null, null, has);
                resultHandler(event, roleName);
            }
            return (has as Boolean);
        }
        
        private function roleResultHandler(event:TideResultEvent, roleName:String):void {
            _rolesCache[roleName] = event.result as Boolean;
            dispatchEvent(new Event("roleChanged"));
        }
        
        private function roleFaultHandler(event:TideFaultEvent, roleName:String):void {
            delete _rolesCache[roleName];
        }
        
        
        private var _permissionsCache:Dictionary = new Dictionary(true);
        
        /**
         *	Check permission for the specified target and action
         *  
         *  @param target target object
         *  @param action requested action
         *  @param resultHandler result handler
         *  @param faultHandler fault handler
         *  @return true is permission granted
         */ 
        [Bindable("permissionChanged")]
        public function hasPermission(target:Object, action:String, resultHandler:Function = null, faultHandler:Function = null):Boolean {
            var cache:Object = _permissionsCache[target];
            if (cache == null || (cache && cache[action] === undefined)) {
                if (loggedIn) {
                    var responder:TidePermissionResponder = new TidePermissionResponder(permissionResultHandler, permissionFaultHandler, target, action);
                    responder.addHandlers(resultHandler, faultHandler);
                    _context.meta_callComponent(_serverSession, this, "hasPermission", [target, action, responder], false);
                    if (cache == null) {
                        cache = new Object();
                        _permissionsCache[target] = cache;
                    }
                    cache[action] = responder;
                }
                return false;
            }
            if (cache[action] is TidePermissionResponder) {
                cache[action].addHandlers(resultHandler, faultHandler);
            	return false;
            }
            
            if (resultHandler != null) {
                var event:TideResultEvent = new TideResultEvent(TideResultEvent.RESULT, _context, false, false, null, null, cache[action]);
                resultHandler(event, target, action);
            }
            return (cache[action] as Boolean);
        }
        
        private function permissionResultHandler(event:TideResultEvent, target:Object, action:String):void {
            _permissionsCache[target][action] = event.result as Boolean;
            dispatchEvent(new Event("permissionChanged"));
        }
        
        private function permissionFaultHandler(event:TideFaultEvent, target:Object, action:String):void {
            delete _permissionsCache[target];
        }
        
        
        private function initSecurityCache():void {
            dispatchEvent(new Event("roleChanged"));
            dispatchEvent(new Event("permissionChanged"));
        }
        
        /**
         * 	Clear the security cache
         */
        public function clearSecurityCache():void {
            _rolesCache = new Object();
            _permissionsCache = new Dictionary(true);
        }
        
        
        public static function instance():Identity {
            return Seam.getInstance().getSeamContext().identity as Identity;
        }
    }
}


import org.granite.tide.ITideResponder;
import org.granite.tide.events.TideResultEvent;
import org.granite.tide.events.TideFaultEvent;


class TideRoleResponder implements ITideResponder {
    
    private var _resultHandlers:Array = new Array();
    private var _faultHandlers:Array = new Array();
    private var _roleName:String;
    
    
    public function TideRoleResponder(resultHandler:Function, faultHandler:Function, roleName:String):void {
        if (resultHandler != null)
            _resultHandlers.push(resultHandler);
        if (faultHandler != null)
            _faultHandlers.push(faultHandler);  
        _roleName = roleName;
    }
    
    public function addHandlers(resultHandler:Function = null, faultHandler:Function = null):void {
        if (resultHandler != null)
            _resultHandlers.push(resultHandler);
        if (faultHandler != null)
            _faultHandlers.push(faultHandler);
    }
    
    
    public function result(event:TideResultEvent):void {
        for each (var resultHandler:Function in _resultHandlers) 
            resultHandler(event, _roleName);
    }
    
    public function fault(event:TideFaultEvent):void {
        for each (var faultHandler:Function in _faultHandlers)
            faultHandler(event, _roleName);
    } 
}


class TidePermissionResponder implements ITideResponder {
    
    private var _resultHandlers:Array = new Array();
    private var _faultHandlers:Array = new Array();
    private var _target:Object;
    private var _action:String;
    
    
    public function TidePermissionResponder(resultHandler:Function, faultHandler:Function, target:Object, action:String):void {
        if (resultHandler != null)
            _resultHandlers.push(resultHandler);
        if (faultHandler != null)
            _faultHandlers.push(faultHandler);
        _target = target;
        _action = action;
    }
    
    public function addHandlers(resultHandler:Function = null, faultHandler:Function = null):void {
        if (resultHandler != null)
            _resultHandlers.push(resultHandler);
        if (faultHandler != null)
            _faultHandlers.push(faultHandler);
    }
    
    
    public function result(event:TideResultEvent):void {
        for each (var resultHandler:Function in _resultHandlers) 
            resultHandler(event, _target, _action);
    }
    
    public function fault(event:TideFaultEvent):void {
        for each (var faultHandler:Function in _faultHandlers)
            faultHandler(event, _target, _action);
    } 
}
