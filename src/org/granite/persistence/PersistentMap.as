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
package org.granite.persistence {

    import flash.utils.IDataInput;
    import flash.utils.IDataOutput;
    
    import mx.events.CollectionEvent;
    import mx.events.CollectionEventKind;
    
    import org.granite.collections.BasicMap;
    import org.granite.collections.IPersistentCollection;
    import org.granite.collections.UIDArraySet;


    [RemoteClass(alias="org.granite.messaging.persistence.ExternalizablePersistentMap")]
    /**
     * @author Francesco FARAONE
     */
    public class PersistentMap extends BasicMap implements IPersistentCollection {

        private var _initializing:Boolean = false;
        private var _initialized:Boolean = false;
        private var _metadata:String = null;
        private var _dirty:Boolean = false;

        public function PersistentMap(initialized:Boolean = true) {
            super(new UIDArraySet());
            _initialized = initialized;
            if (_initialized)
	            addEventListener(CollectionEvent.COLLECTION_CHANGE, dirtyCheckHandler, false, 1000);
        }


        final public function isInitialized():Boolean {
            return _initialized;
        }

        final public function initializing():void {
            clear();
            _initializing = true;
            _dirty = false;
            removeEventListener(CollectionEvent.COLLECTION_CHANGE, dirtyCheckHandler);
        }

        final public function initialize():void {
            _initializing = false;
            _initialized = true;
            _dirty = false;
            addEventListener(CollectionEvent.COLLECTION_CHANGE, dirtyCheckHandler);
        }

        final public function uninitialize():void {
			removeEventListener(CollectionEvent.COLLECTION_CHANGE, dirtyCheckHandler);
			_initialized = false;
            clear();
            _dirty = false;
        }
        
        public function clone():PersistentMap {
        	var map:PersistentMap = new PersistentMap(_initialized);
        	map._metadata = _metadata;
        	map._dirty = _dirty;
        	if (_initialized) {
        		for each (var key:Object in keySet)
        			map.put(key, this.get(key));
        	}
        	return map;
        }
        
        private function dirtyCheckHandler(event:CollectionEvent):void {
            if (!_initialized)
                return;
            if (event.kind == CollectionEventKind.ADD)
                _dirty = true;
            else if (event.kind == CollectionEventKind.REMOVE)
                _dirty = true;
			else if (event.kind == CollectionEventKind.RESET)
				_dirty = true;
			else if (event.kind == CollectionEventKind.REPLACE)
				_dirty = true;
        }


        override public function readExternal(input:IDataInput):void {
            _initialized = input.readObject() as Boolean;
            _metadata = input.readObject() as String;
            if (_initialized) {
                var dirty:Boolean = input.readObject() as Boolean;
                super.readExternal(input);
				_dirty = dirty;	// GDS-1092: Delay assignment of dirty because super.readExternal may have triggered dirtyCheckHandler
            }
			else	// GDS-1092: Added by default by the constructor
				removeEventListener(CollectionEvent.COLLECTION_CHANGE, dirtyCheckHandler);
       }

        override public function writeExternal(output:IDataOutput):void {
            output.writeObject(_initialized);
            output.writeObject(_metadata);
            if (_initialized) {
                output.writeObject(_dirty);
                super.writeExternal(output);
            }
        }
    }
}