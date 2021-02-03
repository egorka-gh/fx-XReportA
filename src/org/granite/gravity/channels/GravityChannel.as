/*
 *   GRANITE DATA SERVICES
 *   Copyright (C) 2006-2014 GRANITE DATA SERVICES S.A.S.
 *
 *   This file is part of the Granite Data Services Platform.
 *
 *   Granite Data Services is free software; you can redistribute it and/or
 *   modify it under the terms of the GNU Lesser General Public
 *   License as published by the Free Software Foundation; either
 *   version 2.1 of the License, or (at your option) any later version.
 *
 *   Granite Data Services is distributed in the hope that it will be useful,
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Lesser
 *   General Public License for more details.
 *
 *   You should have received a copy of the GNU Lesser General Public
 *   License along with this library; if not, write to the Free Software
 *   Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301,
 *   USA, or see <http://www.gnu.org/licenses/>.
 */
package org.granite.gravity.channels {

    import flash.utils.Dictionary;
    
    import mx.logging.ILogger;
    import mx.logging.Log;
    import mx.messaging.Channel;
    import mx.messaging.MessageAgent;
    import mx.messaging.MessageResponder;
    import mx.messaging.events.ChannelFaultEvent;
    import mx.messaging.events.MessageEvent;
    import mx.messaging.messages.AbstractMessage;
    import mx.messaging.messages.AcknowledgeMessage;
    import mx.messaging.messages.CommandMessage;
    import mx.messaging.messages.ErrorMessage;
    import mx.messaging.messages.IMessage;
    import mx.utils.URLUtil;
    
    import org.granite.gravity.Consumer;

	
    /**
     *	Channel implementation for the Gravity Comet based communication with serlvet containers
     *  
     * 	@author Franck WOLFF
     */
    public class GravityChannel extends Channel {
        
        private static var log:ILogger = Log.getLogger("org.granite.gravity.channels.GravityChannel");

        ///////////////////////////////////////////////////////////////////////
        // Fields.

        private var _command:GravityStreamCommand = null;
        private var _tunnel:GravityStreamTunnel = null;
        private var _clientId:String = null;

        private var _consumers:Dictionary = new Dictionary();

		// Sent as advices by the server (on PING via GravityStreamCommand).
		// Default is 30s * 60 * <connection timeout>, ie: more than half an hour,
		// depending on the browser connection timeout.
		private var _reconnectIntervalMs:Number = 30000;
		private var _reconnectMaxAttempts:Number = 60;
		private var _encodeMessageBody:Boolean = false;

        ///////////////////////////////////////////////////////////////////////
        // Constructor.

        public function GravityChannel(id:String, uri:String) {
            super(id, uri);
            _command = new GravityStreamCommand(this);
        }

        ///////////////////////////////////////////////////////////////////////
        // Properties.

        public function get clientId():String {
            return _clientId;
        }

        override public function get protocol():String {
            return 'http';
        }

		public function set reconnectIntervalMs(value:Number):void {
			if (isNaN(value) || value <= 0 || value > Number.MAX_VALUE)
				throw new Error("Reconnect interval must be in ]0, Number.MAX_VALUE]");
			_reconnectIntervalMs = value;
		}
		public function get reconnectIntervalMs():Number {
			return _reconnectIntervalMs;
		}

		public function set reconnectMaxAttempts(value:Number):void {
			if (isNaN(value) || value < 0 || value > Number.MAX_VALUE)
				throw new Error("Reconnect max attempts must be in [0, Number.MAX_VALUE]");
			_reconnectMaxAttempts = value;
		}
		public function get reconnectMaxAttempts():Number {
			return _reconnectMaxAttempts;
		}
		
		public function set encodeMessageBody(value:Boolean):void {
			_encodeMessageBody = value;
		}
		public function get encodeMessageBody():Boolean {
			return _encodeMessageBody;
		}
		
		public function get commandUri():String {
			return (_command != null ? _command.uri : null);
		}
		
		public function get tunnelUri():String {
			return (_tunnel != null ? _tunnel.uri : null);
		}

        ///////////////////////////////////////////////////////////////////////
        // Package protected handlers (used by GravityStream).

        internal function streamConnectSuccess(stream:GravityStream, clientId:String):void {
            if (stream is GravityStreamCommand) {
                _clientId = clientId;
                connectSuccess();
            }
        }
        internal function streamConnectFailed(stream:GravityStream, code:String, e:Error = null):void {
            if (stream is GravityStreamCommand)
                connectFailed(ChannelFaultEvent.createEvent(this, false, code));
        }

        internal function streamDisconnectSuccess(stream:GravityStream, rejected:Boolean = false):void {
            if (stream is GravityStreamCommand) {
                _clientId = null;
                if (_tunnel && _tunnel.connected) {
                    _tunnel.disconnect();
                    _tunnel = null;
                }
                _command = new GravityStreamCommand(this);
                disconnectSuccess(rejected);
            }
        }
        internal function streamDisconnectFailed(stream:GravityStream, code:String, e:Error = null):void {
            if (stream is GravityStreamCommand)
                disconnectFailed(ChannelFaultEvent.createEvent(this, false, code));
        }


        internal function callResponder(responder:MessageResponder, response:IMessage):void {
            var subscriptionId:String = null;
            var consumer:Consumer = null;

			// This is likely when webapp has been reloaded...
        	if ((response is ErrorMessage) && ((response as ErrorMessage).faultCode === "Server.Call.UnknownClient")) {
	            if (_tunnel) {
	            	try {
	                	_tunnel.disconnect();
	                } catch (e:Error) {
	                }
	                _tunnel = null;
	            }
	            if (_command) {
	            	try {
	                	_command.forceDisconnect();
	                } catch (e:Error) {
	                }
	            }
	            _command = new GravityStreamCommand(this);
	            _clientId = null;
        		
        		disconnectSuccess(false);
        		
        		for (subscriptionId in _consumers) {
            		consumer = _consumers[subscriptionId] as Consumer;
            		if (consumer)
            			consumer.resubscribe();
        		}
        		
        		return;
        	}
        	
        	// Normal response processing...
            if (responder is StreamMessageResponder) {
                if (response is ErrorMessage)
                    (responder as StreamMessageResponder).internalStatus(response);
            	else if (response is AcknowledgeMessage)
                    (responder as StreamMessageResponder).internalResult(response);
                else {
                    subscriptionId = response.headers[AbstractMessage.DESTINATION_CLIENT_ID_HEADER] as String;
                    var dispatched:Boolean = false;
                    if (subscriptionId) {
                        consumer = _consumers[subscriptionId] as Consumer;
                        if (consumer) {
                            var messageEvent:MessageEvent = new MessageEvent(MessageEvent.MESSAGE, false, false, response);
                            consumer.dispatchEvent(messageEvent);
                            dispatched = true;
                        }
                    }
                    if (!dispatched)
                        log.debug("callResponder: message not dispatched: unknown subscription {0}", subscriptionId);
                }
            }
            else {
                if (response is ErrorMessage)
                    responder.status(response);
                else {
                    if (responder.message is CommandMessage) {
                        var command:CommandMessage = (responder.message as CommandMessage);
                        if (command.operation == CommandMessage.SUBSCRIBE_OPERATION) {
                            if (!_tunnel)
                                _tunnel = newTunnel();
                            if (!_tunnel.connected)
                                _tunnel.connect(resolveUri());

                            subscriptionId = response.headers[AbstractMessage.DESTINATION_CLIENT_ID_HEADER] as String;
                            consumer = responder.agent as Consumer;
                            
                            // Remove any previous subscription since a Consumer can subscribe only once. Avoid
                            // multiple re-subscription when reconnecting (server restart).
                            var previousSubscriptionId:String = null;
                            for (var id:String in _consumers) {
                            	if (consumer === _consumers[id]) {
                            		previousSubscriptionId = id;
                            		break;
                            	}
                            }
                            if (previousSubscriptionId != null)
                            	delete _consumers[previousSubscriptionId];
                            
                            _consumers[subscriptionId] = consumer;
                        }
                        else if (command.operation == CommandMessage.UNSUBSCRIBE_OPERATION) {
                            subscriptionId = response.headers[AbstractMessage.DESTINATION_CLIENT_ID_HEADER] as String;
                            delete _consumers[subscriptionId];
                        }
                    }
                    responder.result(response);
                }
            }
        }

        ///////////////////////////////////////////////////////////////////////
        // Protected operations.
		
		protected function internalCallResponder(responder:MessageResponder, response:IMessage):void {
			callResponder(responder, response);
		}
		
		protected function get tunnel():GravityStreamTunnel {
			return _tunnel;
		}

		protected function newTunnel():GravityStreamTunnel {
			return new GravityStreamTunnel(this);
		}

        override protected function getMessageResponder(agent:MessageAgent, message:IMessage):MessageResponder {
            return new GravityMessageResponder(agent, message, this);
        }

        override protected function internalConnect():void {
            _command.connect(resolveUri());
        }

        override protected function internalDisconnect(rejected:Boolean = false):void {
			if (!rejected && !shouldBeConnected) {
	            if (_tunnel) {
	            	try {
	                	_tunnel.disconnect();
	                } catch (e:Error) {
	                }
	                _tunnel = null;
	            }
	
	            if (_command) {
	            	try {
	                	_command.disconnect();
	                } catch (e:Error) {
	                }
	            }
	            _command = new GravityStreamCommand(this);
	
	            _clientId = null;
	            _consumers = new Dictionary();
			}
			
			setConnected(false);
			super.internalDisconnect(rejected);
        }

        override protected function internalSend(messageResponder:MessageResponder):void {
            _command.send(messageResponder);
        }

        ///////////////////////////////////////////////////////////////////////
        // Utilities.

        private function resolveUri():String {
            return URLUtil.replaceTokens(uri);
        }
    }
}
