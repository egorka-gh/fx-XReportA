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
package org.granite.tide.data {
	
	import flash.events.Event;
	import flash.events.EventDispatcher;
	import flash.utils.getQualifiedClassName;
	
	import mx.logging.ILogger;
	import mx.logging.Log;
	import mx.messaging.events.ChannelFaultEvent;
	import mx.messaging.events.MessageAckEvent;
	import mx.messaging.events.MessageEvent;
	import mx.messaging.events.MessageFaultEvent;
	
	import org.granite.gravity.Consumer;
	import org.granite.tide.BaseContext;
	import org.granite.tide.IComponent;
	import org.granite.tide.Tide;
	import org.granite.tide.events.TideSubscriptionEvent;
    import org.granite.tide.service.DefaultChannelBuilder;
    import org.granite.tide.service.IServerApp;
    import org.granite.tide.service.ServerSession;
    import org.granite.util.ClassUtil;
    

	[Bindable]
    /**
     * 	The DataObserver component can be bound to a JMS topic and receive updates to managed entities.<br/>
     *  This component encapsulates a Gravity Consumer.<br/>
     *  All updates received are merged in the global context and a Flex event is dispatched to indicate what happened.<br/>
     *  <br/>
     *  The events raised by this component are :<br/>
     *  org.granite.tide.data.persist.&lt;entityName&gt;<br/>
     *  org.granite.tide.data.update.&lt;entityName&gt;<br/>
     *  org.granite.tide.data.remove.&lt;entityName&gt;<br/>
     *  <br/>
     * 	Where &lt;entityName&gt; is the unqualified class name of the entity.<br/>
     * 
     * 	@author William DRAI
     */
	public class DataObserver extends EventDispatcher implements IComponent {
        
        private static var log:ILogger = Log.getLogger("org.granite.tide.data.DataObserver");

        private static const DATA_TOPIC:String = "tideDataTopic";

        private var _serverSession:ServerSession = null;
        private var _type:String = null;
        private var _componentName:String = null;
		private var _consumer:Consumer = null;
		
		private var _name:String;
		private var _context:BaseContext;


        public function DataObserver(serverSession:ServerSession = null, type:String = null):void {
            _serverSession = serverSession;
            _type = (type ? type : DefaultChannelBuilder.LONG_POLLING); 
        }

        public function set serverSession(serverSession:ServerSession):void {
            if (serverSession == _serverSession)
                return;

            _serverSession = serverSession;
            initConsumer();
        }

        public function set type(type:String):void {
            if (type == _type)
                return;

            _type = type;
            initConsumer();
        }

		public function get meta_name():String {
			return _consumer.destination;
		}

		public function meta_init(componentName:String, context:BaseContext):void {
			if (!context.meta_isGlobal())
				throw new Error("Cannot setup DataObserver on conversation context");
			
			context.meta_tide.setComponentRemoteSync(componentName, Tide.SYNC_NONE);
			
		    log.debug("init DataObserver {0}", componentName);
			_context = context;
            _componentName = componentName;
            if (_serverSession == null)
                _serverSession = context.meta_tide.mainServerSession;

            initConsumer();
        }

        private function initConsumer():void {
            if (_componentName == null)
                return;

	        _consumer = _serverSession.getConsumer(_componentName, DATA_TOPIC, _type);
		}
		
		public function meta_clear():void {
			if (_consumer.subscribed)
				unsubscribe();
		}
		
		public function set topic(topic:String):void {
			_consumer.topic = topic;
		}
		
		
		/**
		 * 	Subscribe the data topic
		 */
		public function subscribe():void {
		    _consumer.subscribe();
			_consumer.addEventListener(MessageAckEvent.ACKNOWLEDGE, subscribeHandler);
			_consumer.addEventListener(MessageFaultEvent.FAULT, subscribeFaultHandler);
			_consumer.addEventListener(ChannelFaultEvent.FAULT, subscribeFaultHandler);
		    _consumer.addEventListener(MessageEvent.MESSAGE, messageHandler);
		}
		
		public function subscribeHandler(event:Event):void {
			log.info("destination {0} subscribed", meta_name);
			_consumer.removeEventListener(MessageAckEvent.ACKNOWLEDGE, subscribeHandler);
			_consumer.removeEventListener(MessageFaultEvent.FAULT, subscribeFaultHandler);
			_consumer.removeEventListener(ChannelFaultEvent.FAULT, subscribeFaultHandler);
			dispatchEvent(new TideSubscriptionEvent(TideSubscriptionEvent.TOPIC_SUBSCRIBED));
		}
		
		private function subscribeFaultHandler(event:Event):void {
			log.error("destination {0} could not be subscribed: {1}", meta_name, event.toString());
			_consumer.removeEventListener(MessageAckEvent.ACKNOWLEDGE, subscribeHandler);
			_consumer.removeEventListener(MessageFaultEvent.FAULT, subscribeFaultHandler);
			_consumer.removeEventListener(ChannelFaultEvent.FAULT, subscribeFaultHandler);
			dispatchEvent(new TideSubscriptionEvent(TideSubscriptionEvent.TOPIC_SUBSCRIBED_FAULT));
		}

		/**
		 *  Unsubscribe the data topic
		 */
		public function unsubscribe():void {
			if (!_consumer.connected || !_consumer.subscribed)
				return;
		    _consumer.addEventListener(MessageAckEvent.ACKNOWLEDGE, unsubscribeHandler);
			_consumer.addEventListener(MessageFaultEvent.FAULT, unsubscribeFaultHandler);
			_consumer.addEventListener(ChannelFaultEvent.FAULT, unsubscribeFaultHandler);
            _serverSession.checkWaitForLogout();
		    _consumer.unsubscribe();
		}
		
		private function unsubscribeHandler(event:Event):void {
			log.info("destination {0} unsubscribed", meta_name);
		    _consumer.removeEventListener(MessageAckEvent.ACKNOWLEDGE, unsubscribeHandler);
			_consumer.removeEventListener(MessageFaultEvent.FAULT, unsubscribeFaultHandler);
			_consumer.removeEventListener(ChannelFaultEvent.FAULT, unsubscribeFaultHandler);
	    	_consumer.disconnect();
            _serverSession.tryLogout();
			dispatchEvent(new TideSubscriptionEvent(TideSubscriptionEvent.TOPIC_UNSUBSCRIBED));
		}
		
		private function unsubscribeFaultHandler(event:Event):void {
			log.error("destination {0} could not be unsubscribed: {1}", meta_name, event.toString());
			_consumer.removeEventListener(MessageAckEvent.ACKNOWLEDGE, unsubscribeHandler);
			_consumer.removeEventListener(MessageFaultEvent.FAULT, unsubscribeFaultHandler);
			_consumer.removeEventListener(ChannelFaultEvent.FAULT, unsubscribeFaultHandler);
			_consumer.disconnect();
			_serverSession.tryLogout();
			dispatchEvent(new TideSubscriptionEvent(TideSubscriptionEvent.TOPIC_UNSUBSCRIBED_FAULT));
		}


		/**
		 * 	Message handler that merges data from the JMS topic in the current context.<br/>
		 *  Could be overriden to provide custom behaviour.
		 * 
		 *  @param event message event from the Consumer
		 */
        protected function messageHandler(event:MessageEvent):void {
            log.debug("destination {0} message received {1}", meta_name, event.toString());
            
            // Save the call context because data has not been requested by the current user 
            var savedCallContext:Object = _context.meta_saveAndResetCallContext();
            try {
                var receivedSessionId:String = event.message.headers["GDSSessionID"] as String;
                var updates:Array = event.message.body as Array;
                _context.meta_setServerSession(_serverSession);
                _context.meta_handleUpdates(receivedSessionId != null && receivedSessionId != _serverSession.sessionId, updates);
                _context.meta_handleUpdateEvents(updates);
            }
            finally {
	      	    _context.meta_restoreCallContext(savedCallContext);
            }
        }
	}
}
