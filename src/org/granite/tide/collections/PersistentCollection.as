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
package org.granite.tide.collections {
	  
    import flash.utils.Dictionary;
    import flash.utils.flash_proxy;
    
    import mx.collections.IList;
    import mx.collections.IViewCursor;
    import mx.collections.ItemResponder;
    import mx.collections.ListCollectionView;
    import mx.collections.errors.ItemPendingError;
    import mx.data.utils.Managed;
    import mx.events.CollectionEvent;
    import mx.events.CollectionEventKind;
    import mx.events.PropertyChangeEvent;
    import mx.logging.ILogger;
    import mx.logging.Log;
    import mx.rpc.AsyncToken;
    import mx.rpc.IResponder;
    import mx.rpc.events.ResultEvent;
    import mx.utils.object_proxy;
    
    import org.granite.collections.IPersistentCollection;
    import org.granite.tide.BaseContext;
    import org.granite.tide.IEntity;
    import org.granite.tide.IEntityManager;
    import org.granite.tide.IPropertyHolder;
    import org.granite.tide.IWrapper;
    import org.granite.tide.data.EntityManager;
    import org.granite.tide.service.ServerSession;

    use namespace flash_proxy;
    use namespace object_proxy;
    

	[Event(name="initialize", type="mx.events.CollectionEvent")]
	[Event(name="uninitialize", type="mx.events.CollectionEvent")]
	
    /**
     * 	Internal implementation of persistent collection handling automatic lazy loading.<br/>
     *  Used for wrapping persistent collections received from the server.<br/>
     * 	Should not be used directly.
     * 
     * 	@author William DRAI
     */
	public class PersistentCollection extends ListCollectionView implements IPersistentCollection, IPropertyHolder, IWrapper {
        
        private static var log:ILogger = Log.getLogger("org.granite.tide.collections.PersistentCollection");

        private var _serverSession:ServerSession = null;
	    private var _entity:IEntity = null;
	    private var _propertyName:String = null;
	
	    private var _localInitializing:Boolean = false;
        private var _itemPendingError:ItemPendingError = null;
        private var _initializationCallbacks:Array = null;
	    
	    
        public function get entity():Object {
        	return _entity;
        } 
	    
        public function get propertyName():String {
        	return _propertyName;
        }
		
		public function PersistentCollection(serverSession:ServerSession, entity:IEntity, propertyName:String, collection:IPersistentCollection) {
		    super(IList(collection));
            _serverSession = serverSession;
		    _entity = entity;
		    _propertyName = propertyName;
		}

        public function set serverSession(serverSession:ServerSession):void {
            _serverSession = serverSession;
        }
		
        
        public function get object():Object {
            return list;
        }
        
        public function isInitialized():Boolean {
            return IPersistentCollection(list).isInitialized();
        }
        
        public function isInitializing():Boolean {
            return _itemPendingError != null;
        }
        
        public function initializing():void {
            IPersistentCollection(list).initializing();
            _localInitializing = true;
        }
        
        private function requestInitialization():void {
        	var em:IEntityManager = Managed.getEntityManager(_entity);
            if (_localInitializing || BaseContext(em).meta_lazyInitializationDisabled)
                return;
            
            if (!_itemPendingError) {
                log.debug("initialization requested " + toString());
                em.meta_initializeObject(_serverSession, this);
                
                _itemPendingError = new ItemPendingError("PersistentCollection initializing");
            }
            
            // throw _itemPendingError;
        }
        
        public function initialize():void {
            IPersistentCollection(list).initialize();
            _localInitializing = false;
            
            if (_itemPendingError) {
                var event:ResultEvent = new ResultEvent(ResultEvent.RESULT, false, true, this);
                log.debug("notify item pending");
                
                if (_itemPendingError.responders) {
                    for (var k:int = 0; k < _itemPendingError.responders.length; k++)
                        _itemPendingError.responders[k].result(event);
                }
                
                _itemPendingError = null;
            }
            
            if (_initializationCallbacks != null) {
				for each (var callback:Function in _initializationCallbacks)
					callback(this);
            	_initializationCallbacks = null;
            }
            
            dispatchEvent(new CollectionEvent(CollectionEvent.COLLECTION_CHANGE, false, false, CollectionEventKind.REFRESH));
			dispatchEvent(new CollectionEvent(CollectionEvent.COLLECTION_CHANGE, false, false, EntityManager.INITIALIZE));
			entity.dispatchEvent(new PropertyChangeEvent(EntityManager.LOAD_STATE_CHANGE, false, false, EntityManager.INITIALIZE, propertyName, null, list, entity));
            
            log.debug("initialized");
        }
        
        public function uninitialize():void {
            IPersistentCollection(list).uninitialize();
            _itemPendingError = null;
        	_initializationCallbacks = null;
            _localInitializing = false;
            
            dispatchEvent(new CollectionEvent(CollectionEvent.COLLECTION_CHANGE, false, false, CollectionEventKind.REFRESH));
			dispatchEvent(new CollectionEvent(CollectionEvent.COLLECTION_CHANGE, false, false, EntityManager.UNINITIALIZE));
			entity.dispatchEvent(new PropertyChangeEvent(EntityManager.LOAD_STATE_CHANGE, false, false, EntityManager.UNINITIALIZE, propertyName, null, list, entity));
			
			log.debug("uninitialized");
        }
        
        
        public function meta_propertyResultHandler(propName:String, event:ResultEvent):void {
        }
        
        
		public function withInitialized(callback:Function):void {
			if (isInitialized())
				callback(this);
			else {
				if (_initializationCallbacks == null)
					_initializationCallbacks = [];
				_initializationCallbacks.push(callback);
				requestInitialization();
			}
		}
		
		public function reload():void {
			var em:IEntityManager = Managed.getEntityManager(_entity);
			if (_localInitializing)
				return;
			
			log.debug("forced reload requested " + toString());
			em.meta_initializeObject(_serverSession, this);
		}
		
        
		[Bindable("collectionChange")]
        public override function get length():int {
            if (_localInitializing || isInitialized())
                return super.length;
            
            requestInitialization();
            return 0;
//	        // Must be initialized to >0 to enable ItemPendingError at first getItemAt
//	        var em:IEntityManager = Managed.getEntityManager(_entity);
//			return (em && !BaseContext(em).meta_lazyInitializationDisabled) ? 1 : 0;
        }
        
        public override function getItemAt(index:int, prefetch:int=0):Object {
            if (_localInitializing || isInitialized())
                return super.getItemAt(index, prefetch);
            
            requestInitialization();
            return null;
        }
        
        public override function addItem(item:Object):void {
            if (_localInitializing || isInitialized()) {
                super.addItem(item);
                return;
            }
            
            throw new Error("Cannot modify uninitialized collection: " + _entity + " property " + propertyName); 
        }
        
        public override function addItemAt(item:Object, index:int):void {
            if (_localInitializing || isInitialized()) {
                super.addItemAt(item, index);
                return;
            }
            
            throw new Error("Cannot modify uninitialized collection: " + _entity + " property " + propertyName); 
        }
		
		public override function addAllAt(addList:IList, index:int):void { 
			if (!(_localInitializing || isInitialized()))
				throw new Error("Cannot modify uninitialized collection: " + _entity + " property " + propertyName); 
			
			var length:int = addList.length; 
			var position:int = 0; 
			for (var i:int = 0; i < length; i++) { 
				var oldLength:int = this.length; 
				this.addItemAt(addList.getItemAt(i), position+index); 
				if (oldLength < this.length) 
					position++;
			} 
		}
        
        public override function setItemAt(item:Object, index:int):Object {
            if (_localInitializing || isInitialized())
                return super.setItemAt(item, index);
            
            throw new Error("Cannot modify uninitialized collection: " + _entity + " property " + propertyName); 
        }
        
        public override function removeItemAt(index:int):Object {
            if (_localInitializing || isInitialized())
                return super.removeItemAt(index);
            
            throw new Error("Cannot modify uninitialized collection: " + _entity + " property " + propertyName); 
        }
        
        public override function removeAll():void {
            if (_localInitializing || isInitialized()) {
                super.removeAll();
                return;
            }
            super.removeAll();
            initialize();
        }
                
        public override function refresh():Boolean {
            if (_localInitializing || isInitialized())
	        	return super.refresh();
	        
	        requestInitialization();
	        return false;
        }
		
        
        public override function toString():String {
            if (isInitialized())
                return "Initialized collection for object: " + BaseContext.toString(_entity) + " " + _propertyName + ": " + super.toString();
            
            return "Uninitialized collection for object: " + BaseContext.toString(_entity) + " " + _propertyName;
        }
	}
}
