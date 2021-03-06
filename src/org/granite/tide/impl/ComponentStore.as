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
package org.granite.tide.impl { 
	
	import flash.events.Event;
	import flash.system.ApplicationDomain;
	import flash.utils.Dictionary;
	import flash.utils.getQualifiedClassName;
	
	import mx.collections.ArrayCollection;
	import mx.collections.IList;
	import mx.collections.Sort;
	import mx.core.IUIComponent;
	import mx.events.FlexEvent;
	import mx.logging.ILogger;
	import mx.logging.Log;
	import mx.utils.ObjectUtil;
	import mx.utils.StringUtil;
	
	import org.granite.reflect.Annotation;
	import org.granite.reflect.Field;
	import org.granite.reflect.Method;
	import org.granite.reflect.Parameter;
	import org.granite.reflect.Type;
	import org.granite.tide.BaseContext;
	import org.granite.tide.ComponentDescriptor;
	import org.granite.tide.IContextManager;
	import org.granite.tide.IEntity;
	import org.granite.tide.ITideModule;
	import org.granite.tide.Subcontext;
	import org.granite.tide.Tide;
	import org.granite.tide.events.TideContextEvent;
	import org.granite.tide.events.TidePluginEvent;
	import org.granite.util.ClassUtil;
    

	[Bindable]
    /**
	 *  ComponentStore stores component descriptors
	 *
     * 	@author William DRAI
     */
	public class ComponentStore {
        
        private static var log:ILogger = Log.getLogger("org.granite.tide.impl.ComponentStore");
        
        private var _tide:Tide;
        private var _contextManager:IContextManager;
        
		private var _moduleComponents:Dictionary = new Dictionary(true);
		private var _componentDescriptors:Dictionary = new Dictionary();
		private var _observersByType:Dictionary = new Dictionary();
		private var _allProducersByType:Dictionary = new Dictionary();
		private var _injectionPointsByType:Dictionary = new Dictionary();
		
        private var _modules:Dictionary = new Dictionary();
        private var _moduleRef:Dictionary = new Dictionary();
		private var _moduleApplicationDomain:Dictionary = new Dictionary(true);
		private var _applicationDomains:Dictionary = new Dictionary(true);

		
		public function ComponentStore(tide:Tide, contextManager:IContextManager):void {
			_tide = tide;
			_contextManager = contextManager;
		}
		
		
		/**
		 * 	@private
		 *  
		 * 	Get implementation producer for type
		 * 
		 *  @param type class required at injection point
		 *  @return name of implementation component
		 */
		public function getProducer(type:Class):IComponentProducer {
			var producers:Array = _allProducersByType[type];
			return producers && producers.length > 0 ? producers[0] : null;
		}
		
		/**
		 * 	@private
		 *  
		 * 	Get all implementations for type
		 * 
		 *  @param type class required at injection point
		 *  @return array of names of implementation components 
		 */
		public function getAllProducers(type:Class):Array {
			var producers:Array = _allProducersByType[type] as Array;
			return producers ? producers : null;
		}
		
				
		/**
		 * 	@private
		 *  
		 * 	Register a component implementation producer for a type
		 * 
		 *  @param type type class
		 *  @param name of implementation component
		 */
		private function registerProducer(type:Type, producer:IComponentProducer):void {
			var producers:Array = _allProducersByType[type.getClass()] as Array;
			if (producers == null) {
				producers = [];
				_allProducersByType[type.getClass()] = producers;
			}
			
			var found:Boolean = false;
			for each (var p:IComponentProducer in producers) {
				if (p.componentName == producer.componentName) {
					found = true;
					break;
				}
			}
			if (!found) {
				producers.push(producer);
				if (producers.length > 1)
					log.info("Many implementation producers for type " + type.name + ", " + producer.componentName + " will be ignored for [Inject]");
			}
		}
		
		private function registerSimpleProducer(type:Type, name:String):void {
			if (isFrameworkType(type.name))
				return;
			
			var producer:IComponentProducer = new SimpleComponentProducer(name);
			registerProducer(type, producer);
		}
		
		private function registerMethodProducer(type:Type, name:String, method:Method):void {
			if (isFrameworkType(type.name))
				return;
			
			var producer:IComponentProducer = new MethodComponentProducer(name, method);
			registerProducer(type, producer);
		}
		
		private function registerPropertyProducer(type:Type, name:String, field:Field):void {
			if (isFrameworkType(type.name))
				return;
			
			var producer:IComponentProducer = new PropertyComponentProducer(name, field);
			registerProducer(type, producer);
		}
		
		
		/**
		 * 	@private
		 *  
		 * 	Unregister a component implementation for a type
		 * 	
		 *  @param type type class
		 *  @param name of implementation component
		 */
		private function unregisterProducer(name:String):void {
			var typesToRemove:Array = [];
			var producer:IComponentProducer;
            var type:Object;
			for (type in _allProducersByType) {
				var producers:Array = _allProducersByType[type] as Array;
				var idx:int = -1;
				for (var i:int = 0; i < producers.length; i++) {
					if (producers[i].componentName == name) {
						idx = i;
						break;
					}
				}
				if (idx >= 0)
					producers.splice(idx, 1);
				
				if (producers.length == 0)
					typesToRemove.push(type)
			}
			for each (type in typesToRemove)
				delete _allProducersByType[type];
		}
		
		/**
		 * 	@private
		 *  
		 * 	Get injection points for type
		 * 
		 *  @param type type required at injection point
		 *  @return array of injection points [ componentName, propertyName ]
		 */
		public function getInjectionPoints(type:Type):Array {
			var injectionPoints:Array = _injectionPointsByType[type];
			return injectionPoints ? injectionPoints : null;
		}
				
		/**
		 * 	@private
		 *  
		 * 	Register an injection point for a type
		 * 
		 *  @param type type class
		 *  @param componentName target component name
		 *  @param propertyName target property name
		 */
		private function registerInjectionPoint(type:Type, componentName:String, propertyName:String):void {
			if (isFrameworkType(type.name))
				return;
			
			var ips:Array = _injectionPointsByType[type] as Array;
			if (ips == null) {
				ips = [];
				_injectionPointsByType[type] = ips;
			}
			var found:Boolean = false;
			for each (var ip:Array in ips) {
				if (ip[0] == componentName && ip[1] == propertyName) {
					found = true;
					break;
				}
			}
			if (!found)
				ips.push([ componentName, propertyName ]);
		}
		
		private function unregisterInjectionPoints(componentName:String):void {
		    var typeNamesToDelete:Array = [];
		    var type:Object;
		    for (type in _injectionPointsByType) {
		    	var ips:Array = _injectionPointsByType[type];
		    	for (var j:int = 0; j < ips.length; j++) {
		    		if (ips[j][0] == componentName) {
		    			ips.splice(j, 1);
		    			j--;
		    		}
		    		if (ips.length == 0)
		    			typeNamesToDelete.push(type);
		    	}
		    }
		    for each (type in typeNamesToDelete)
		    	delete _injectionPointsByType[type];
		}	
		
		private function isFrameworkType(typeName:String):Boolean {
			return isFxClass(typeName) || typeName == "Object" || typeName == "org.granite.tide::IComponent" || typeName == "org.granite.tide::IPropertyHolder";
		}
		
				
		/**
		 * 	@private
		 *  
		 * 	Get array of types for type (class, superclass, interfaces)
		 * 
		 *  @param type the type
		 *  @return types
		 */
		public function getComponentTypes(type:Type):Array {
			var types:Array = [type].concat(type.superclasses).concat(type.interfaces);
			return types.filter(function(item:*, index:int, array:Array):Boolean {
				return !isFrameworkType(String(item.name));
			});
		}
				
		/**
		 * 	@private
		 * 
		 *  Check if a class name is a Flex framework class
		 * 
		 *  @param className class name
		 *  @return true if class package name is a Flex one
		 */ 
		public function isFxClass(className:String):Boolean {
			return className.substring(0, 3) == 'mx.' 
				|| className.substring(0, 6) == 'flash.' 
				|| className.substring(0, 7) == 'flashx.' 
				|| className.substring(0, 6) == 'spark.' 
				|| className.substring(0, 4) == 'air.' 
				|| className.substring(0, 3) == 'fl.';
		}
		
		
        private var _currentDomain:ApplicationDomain = ApplicationDomain.currentDomain;
		private var _moduleInitializing:Object = null;

		/**
		 * 	Register a Tide module
		 * 
		 * 	@param module the module class or instance (that may implement ITideModule)
		 * 	@param appDomain the Flex application domain for modules loaded dynamically
		 */
		public function addModule(module:Object, appDomain:ApplicationDomain = null):void {
		    if (appDomain != null)
		        Type.registerDomain(appDomain);

            var moduleClass:Class = module is Class ? module as Class : Type.forName(getQualifiedClassName(module), appDomain).getClass();

            if (!(module is Class)) {
                var refs:Object = _moduleRef[moduleClass];
                if (refs == null)
                    _moduleRef[moduleClass] = 1;
                else {
                    _moduleRef[moduleClass] = Number(refs)+1;
                    return;     // Module class already registered
                }
            }

		    var moduleInstance:Object = _modules[moduleClass];
		    if (moduleInstance == null) {
		        moduleInstance = module is Class ? new moduleClass() : module;
		        _modules[moduleClass] = moduleInstance;
		        _moduleInitializing = moduleInstance;
		        _moduleComponents[moduleInstance] = [];
		        if (appDomain != null)
	                _moduleApplicationDomain[moduleInstance] = appDomain;
		        				
		        try {
					if (Object(moduleInstance).hasOwnProperty("moduleName"))
						addSubcontext(Object(moduleInstance).moduleName);

                    if (moduleInstance is ITideModule)
		                ITideModule(moduleInstance).init(_tide);
		        }
		        catch (e:Error) {
		            log.error("Module {0} initialization failed: {1}", getQualifiedClassName(moduleClass), e);
		            throw e; 
		        }
		        _moduleInitializing = null;
		    }
		    else
		        throw new Error("Module " + moduleClass + " already added");
		}

        public function trackModuleCreation(moduleInstance:Object):void {
            if (_moduleComponents[moduleInstance] == null)
                return;
			log.info("Started tracking module {0}", getQualifiedClassName(moduleInstance));
            _moduleInitializing = moduleInstance;
            moduleInstance.addEventListener(FlexEvent.CREATION_COMPLETE, moduleCreationCompleteHandler, false, 0, true);
            moduleInstance.addEventListener(Event.REMOVED, moduleRemovedHandler, false, 0, true);
        }

        private function moduleCreationCompleteHandler(event:FlexEvent):void {
            event.target.removeEventListener(FlexEvent.CREATION_COMPLETE, moduleCreationCompleteHandler);
            _moduleInitializing = null;
			log.info("Module {0} created", getQualifiedClassName(event.target));
        }

        private function moduleRemovedHandler(event:Event):void {
            if (_moduleComponents[event.target] != null) {
				event.target.removeEventListener(Event.REMOVED, moduleRemovedHandler);
                removeModule(event.target);
				log.info("Remved module {0}", getQualifiedClassName(event.target));
			}				
        }


		/**
		 * 	Unregister a Tide module
		 * 
		 * 	@param module the module class or instance (that must implement ITideModule)
		 */
		public function removeModule(module:Object):void {
            if (!(module is Class) && _moduleComponents[module] == null)
                return;     // Module already removed

			var appDomain:ApplicationDomain = module is Class ? null : _moduleApplicationDomain[module];
			
			var moduleClass:Class = module is Class ? module as Class : Type.forName(getQualifiedClassName(module), appDomain).getClass();

            if (!(module is Class)) {
                var refs:Object = _moduleRef[moduleClass];
                if (Number(refs) > 1) {
                    _moduleRef[moduleClass] = Number(refs)-1;
                    return;
                }
            }

		    var moduleInstance:Object = module is Class ? _modules[moduleClass] : module;
		    if (moduleInstance == null)
		        throw new Error("Module " + moduleClass + " not found");
			
			appDomain = _moduleApplicationDomain[moduleInstance];			
					        
		    var componentNames:Array = _moduleComponents[moduleInstance] as Array;
		    for each (var name:String in componentNames)
		        removeComponent(name);
		        
		    delete _moduleApplicationDomain[moduleInstance];
		    delete _moduleComponents[moduleInstance];
		    delete _modules[moduleClass];
            delete _moduleRef[moduleClass];
		    
		    if (appDomain != null)
		        removeApplicationDomain(appDomain);
        }
        
		/**
		 *  @private
		 * 
		 * 	Unregister all Tide components from a Flex application domain 
		 * 
		 *  @param applicationDomain Flex application domain to clear
		 *  @param withModules also removes all components from modules which are defined in the app domain
		 */
        private function removeApplicationDomain(applicationDomain:ApplicationDomain, withModules:Boolean = true):void {
            if (_applicationDomains[applicationDomain] == null)
                throw new Error("ApplicationDomain " + applicationDomain + " is not managed by Tide");
            
            for each (var desc:ComponentDescriptor in _componentDescriptors) {
            	if (desc.factory != null && desc.factory.type.domain === applicationDomain)
                    removeComponent(desc.name);
            }
            
            for (var moduleClass:Object in _modules) {
                if (_moduleApplicationDomain[_modules[moduleClass]] === applicationDomain)
                    removeModule(Class(moduleClass));
            }
            
            delete _applicationDomains[applicationDomain];
            
	        Type.unregisterDomain(applicationDomain);
		}


		private static const EVENT_TYPE:Type = Type.forClass(Event); 
		
		/**
		 *  @private
		 * 	Internal implementation of component registration
		 * 
		 * 	@param name component name
		 * 	@param type component type
		 *  @param properties a factory object containing values to inject in the component instance
		 *  @param inConversation true if the component is conversation-scoped
		 *  @param autoCreate true if the component needs to be automatically instantiated
		 *  @param restrict true if the component needs to be cleared when the user is not logged in
		 *  @param overrideIfPresent allows to override an existing component definition (should normally only be used internally)
		 */
		public function internalAddComponent(name:String, type:Type, properties:Object, inConversation:Boolean = false, autoCreate:Boolean = true, restrict:int = 0, 
			overrideIfPresent:Boolean = true):void {
			
			var factory:ComponentFactory = new ComponentFactory(type, properties);
			
			if (type.isInterface())
				throw new Error("Cannot register interface " + type + " as component class");

			var isRemoteProxy:Boolean = type.fastImplementsInterface(Tide.QCN_ICOMPONENT);
            var isGlobal:Boolean = (
				type.getClass() === Subcontext || isRemoteProxy ||
				(type.getAnnotationArgValueNoCache('Name', 'global') === 'true')
			);
			
			if (_moduleInitializing != null && name.indexOf(".") < 0 
				&& Object(_moduleInitializing).hasOwnProperty("moduleName") && !isGlobal)
				name = Object(_moduleInitializing).moduleName + "." + name;
			
			if (!isGlobal) {
				var idx:int = name.lastIndexOf(".");
				if (idx > 0)
					addSubcontext(name.substring(0, idx));
			}
			
			var descriptor:ComponentDescriptor = getDescriptor(name, false);
		    if (descriptor != null && !overrideIfPresent)
		        return;
		    
		    if (descriptor == null)
		    	descriptor = getDescriptor(name);
		    
		    if (_moduleInitializing != null) {
		        if (_moduleComponents[_moduleInitializing].indexOf(name) < 0)
		            _moduleComponents[_moduleInitializing].push(name);
		    }
		    
	    	descriptor.factory = factory;
		    descriptor.global = isGlobal;
		    descriptor.scope = isRemoteProxy ? Tide.SCOPE_EVENT : (inConversation ? Tide.SCOPE_CONVERSATION : Tide.SCOPE_SESSION);
		    descriptor.autoCreate = autoCreate;
		    descriptor.restrict = restrict;
			for each (var anno:Annotation in type.getAnnotationsNoCache("ManagedEvent"))
				descriptor.events.push(anno.getArgValue("name")); 
		    descriptor.types = getComponentTypes(type);

			if (descriptor.types.indexOf("org.granite.tide::IEntity") < 0) {
				for each (var t:Type in descriptor.types) {
					if (t.name == "org.granite.tide::IComponent" || t.name == "org.granite.tide::Component")
						continue;
						 
					registerSimpleProducer(t, name);
				}
			}
		    
		    _applicationDomains[type.domain] = true;
            
            // Initialize component
            
            if (isRemoteProxy)
            	descriptor.remoteSync = Tide.SYNC_BIDIRECTIONAL;

            if (!ClassUtil.isTopLevel(type.getClass())
            	&& !ClassUtil.isFlashClass(type.getClass()) && !ClassUtil.isMxClass(type.getClass())
            	&& !ClassUtil.isMathClass(type.getClass())) {
            	
				var methods:Array = type.getAnnotatedMethodsNoCache('Observer'),
					method:Method;
	            
				for each (method in methods) {
					var observers:Array = method.getAnnotationsNoCache('Observer');
					for each (var observer:Annotation in observers) { 
		                var remote:Boolean = observer.getArgValue('remote') === "true";
		                var create:Boolean = !(observer.getArgValue('create') === "false");
		                var localOnly:Boolean = observer.getArgValue('localOnly') === "true";
		                var eventTypes:String = observer.getArgValue();
						var te:Type = null;
		                if (eventTypes == null || StringUtil.trim(eventTypes).length == 0) {
							if (method.parameters.length != 1)
								throw new Error("Typed observer method should have one parameter: " + method.name);
							te = Parameter(method.parameters[0]).type;
		                	eventTypes = "$TideEvent$" + (te.alias ? te.alias : te.name);
						}
						else if (method.parameters.length == 1 
								&& Parameter(method.parameters[0]).type.getClass() != TideContextEvent 
								&& Parameter(method.parameters[0]).type.isSubclassOf(EVENT_TYPE)) {
							te = Parameter(method.parameters[0]).type;
							eventTypes = "$TideEvent$" + (te.alias ? te.alias : te.name) + "@" + eventTypes;
                        }
		                var eventTypeArray:Array = eventTypes.split(",");
		                for each (var eventType:String in eventTypeArray)
		                	internalAddEventObserver(StringUtil.trim(eventType), name, method, remote, create, localOnly);
		          	}
				}
	            
				methods = type.getAnnotatedMethodsNoCache('PostConstruct');
				if (methods.length > 0)
					descriptor.postConstructMethodName = Method(methods[0]).name;
				
				methods = type.getAnnotatedMethodsNoCache('Destroy');
				if (methods.length > 0)
					descriptor.destroyMethodName = Method(methods[0]).name;
	            
	            var modulePrefix:String = Tide.getModulePrefix(name);
	            
	            if (properties != null)
	                scanPropertyInjections(properties, type, modulePrefix, inConversation, restrict);
	            
	            setupDescriptor(name, descriptor);
	            
	            scanInjections(name, type, modulePrefix, inConversation, restrict);
	            
	            scanOutjections(type, modulePrefix, inConversation, restrict);
	            
	            scanProducerMethods(name, type, modulePrefix, inConversation, restrict);
	            scanProducerProperties(name, type, modulePrefix, inConversation, restrict);
	        }
            
            _tide.dispatchEvent(new TidePluginEvent(Tide.PLUGIN_ADD_COMPONENT, { descriptor: descriptor, type: type }));
		}
		
		
		/**
		 * 	Register a Tide namespace
		 * 
		 * 	@param name component name
		 */
		public function addSubcontext(name:String):void {
		    if (!isComponent(name) 
		    	|| getDescriptor(name).factory == null 
		    	|| getDescriptor(name).factory.type.getClass() !== Subcontext) {
    		    internalAddComponent(name, Tide.TYPE_SUBCONTEXT, null);
    		}
		}
		
		
		/**
		 * 	@private
		 * 	Internal implementation of component definition annotation scanning
		 * 
		 *  @param modulePrefix current module prefix
		 * 	@param name component name
		 *  @param type component type
		 *  @param global should be in global module
		 *  @param inConversation the component is conversation scoped
		 *  @param remote should be defined as remote 
		 *  @param autoCreate the component is auto instantiated
		 *  @param restrict the component is secured
		 */
		private function addComponentFromType(modulePrefix:String, name:String, type:Type, global:Boolean, inConversation:Boolean, remote:String, autoCreate:String, restrict:int):void {
            
			if (type.getClass() === BaseContext || type.fastExtendsClass(Tide.QCN_BASECONTEXT) || type.isInterface())
            	return;
            
			if (type.fastImplementsInterface(Tide.QCN_ICOMPONENT)) {
                internalAddComponent(name, type, null, inConversation, autoCreate != "false", restrict, false);
                if (global)
	            	_tide.setComponentGlobal(name, true);
             	return;
            }
            
            if (!global)
            	name = modulePrefix + name;
            
            if (type.getClass() === IEntity || type.fastImplementsInterface(Tide.QCN_IENTITY) || type.alias.length > 0 || type.hasDeclaredConstructor()) {
                internalAddComponent(name, type, null, inConversation, autoCreate == "true", restrict, false);
                if (global)
	            	setComponentGlobal(name, true);
                if (remote)
                	setComponentRemoteSync(name, remote == 'true' || remote == 'bidirectional' ? Tide.SYNC_BIDIRECTIONAL : (remote == 'serverToClient' ? Tide.SYNC_SERVER_TO_CLIENT : Tide.SYNC_NONE));
                return;
            }
            if (type.getClass() === IList || type.fastImplementsInterface(Tide.QCN_ILIST)) {
                internalAddComponent(name, type, null, inConversation, autoCreate == "true", restrict, false);
                if (global)
	            	setComponentGlobal(name, true);
                if (remote)
                	setComponentRemoteSync(name, remote == 'true' || remote == 'bidirectional' ? Tide.SYNC_BIDIRECTIONAL : (remote == 'serverToClient' ? Tide.SYNC_SERVER_TO_CLIENT : Tide.SYNC_NONE));
                return;
            }
            if (type.getClass() === IUIComponent || type.fastImplementsInterface(Tide.QCN_IUICOMPONENT)) {
                internalAddComponent(name, type, null, inConversation, autoCreate == "true", restrict, false);
                if (global)
	            	setComponentGlobal(name, true);
                if (remote)
                	setComponentRemoteSync(name, remote == 'true' || remote == 'bidirectional' ? Tide.SYNC_BIDIRECTIONAL : (remote == 'serverToClient' ? Tide.SYNC_SERVER_TO_CLIENT : Tide.SYNC_NONE));
                return;
            }
        }
        
        
		/**
		 * 	@private
		 * 	Internal implementation of observer registration
		 * 
		 * 	@param eventType event type
		 *  @param name name of observer component
		 *  @param m XML fragment of describeType for observer method
		 *  @param remote observer for remote events 
		 *  @param create observer should be instantiated if not existent
		 *  @param localOnly observer does not observe events localOnly from inner contexts/subcontexts
		 */
        public function internalAddEventObserver(eventType:String, name:String, m:Method, remote:Boolean, create:Boolean, localOnly:Boolean):void {
        	var methodName:Object = m.name;
			var type:String = null;
			var idx:int = eventType.lastIndexOf("@");
			if (idx > 0) {
				type = eventType.substring(idx+1);
				eventType = eventType.substring(0, idx);
			}
        	var uri:String = m.uri;
        	if (uri)
        		methodName = new QName(uri, methodName);
            var names:ArrayCollection = _observersByType[eventType] as ArrayCollection;
            if (names == null) {
                names = new ArrayCollection();
                // GDS-627
                var sort:Sort = new Sort();
                sort.compareFunction = subcontextSortDescending;
                names.sort = sort;
                names.refresh();
                _observersByType[eventType] = names;
            }
            var found:Boolean = false;
            for each (var o:Object in names) {
                if (o.name == name && o.methodName == methodName) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                var p:Array = m.parameters;
                names.addItem({
                	name: name, 
                	methodName: methodName, 
                    event: (p.length == 1 && Parameter(p[0]).type.getClass() == TideContextEvent),
					type: type,
                    argumentsCount: p.length,
                    create: create,
                    localOnly: localOnly
                });
                names.refresh();
            }
            
            if (remote)
                _tide.addRemoteEventListener(eventType, null);
	  	}
                
        private function subcontextSortDescending(a:Object, b:Object, fields:Array = null):int {
       		var asn:String = Tide.getModulePrefix(a.name);
       		var bsn:String = Tide.getModulePrefix(b.name);
       		return -(ObjectUtil.stringCompare(asn, bsn));
        }
        
		
		/**
		 * 	@private
		 * 	Internal implementation of injections annotation scanning
		 * 
		 *  @param componentName scanned component name
		 * 	@param type bean type
		 *  @param modulePrefix current module prefix
		 *  @param inConversation the component is conversation scoped
		 *  @param autoCreate the component is auto instantiated
		 *  @param restrict the component is secured
		 */
		private function scanInjections(componentName:String, type:Type, modulePrefix:String, inConversation:Boolean, restrict:int):void {
			TypeScanner.scanInjections(null, type,
				function(context:BaseContext, field:Field, annotation:Annotation, sourcePropName:String, destPropName:Object, create:String, global:String, remote:String):void {
					var name:String;
					if (annotation.name == 'Inject') {
	                    name = Tide.internalNameForTypedComponent(field.type.name + '_' + field.type.id);
	                    
	                    if ((!modulePrefix && !isComponent(name)) || (modulePrefix && !isComponent(modulePrefix + name))) {
	                    	addComponentFromType(modulePrefix, name, field.type, 
	                    		global == 'true', inConversation, remote,
	                    		remote == 'true' ? 'true' : create, Tide.RESTRICT_UNKNOWN
	                    	);
	                    }
	                    
	                	registerInjectionPoint(field.type, componentName, field.name);
					}
					else {
	                    if (sourcePropName.match(/#{.*}/))
	                        return;
	                    
	                    name = field.name;
	                    if (sourcePropName != null && sourcePropName.length > 0)
	                        name = sourcePropName;
	                    
	                    if ((!modulePrefix && !isComponent(name)) || (modulePrefix && !isComponent(modulePrefix + name))) {
	                    	addComponentFromType(modulePrefix, name, field.type, 
	                    		global == 'true', inConversation, remote,
								remote == 'true' ? 'true' : create, Tide.RESTRICT_UNKNOWN
	                    	);
	                    }
					}
				}
			);
		}		
		
		/**
		 * 	@private
		 * 	Internal implementation of outjections annotation scanning
		 * 
		 * 	@param type bean type
		 *  @param modulePrefix current module prefix
		 *  @param inConversation the component is conversation scoped
		 *  @param autoCreate the component is auto instantiated
		 *  @param restrict the component is secured
		 */
		private function scanOutjections(type:Type, modulePrefix:String, inConversation:Boolean, restrict:int):void {
			TypeScanner.scanOutjections(null, type,
				function(context:BaseContext, field:Field, annotation:Annotation, sourcePropName:Object, destPropName:String, global:String, remote:String):void {
	                if ((!modulePrefix && !isComponent(destPropName))
	                	|| (modulePrefix && !isComponent(modulePrefix + destPropName))) {
	                    addComponentFromType(modulePrefix, destPropName, field.type, 
	                    	global == 'true', inConversation, remote, 
	                    	null, Tide.RESTRICT_UNKNOWN);
	                }
	                else if (remote)
	                	setComponentRemoteSync(destPropName, remote == 'true' || remote == 'bidirectional' ? Tide.SYNC_BIDIRECTIONAL : (remote == 'serverToClient' ? Tide.SYNC_SERVER_TO_CLIENT : Tide.SYNC_NONE));
				}
			);
		}
		
		/**
		 * 	@private
		 * 	Internal implementation of producer methods annotation scanning
		 * 
		 *  @param name component name
		 * 	@param type bean type
		 *  @param modulePrefix current module prefix
		 *  @param inConversation the component is conversation scoped
		 *  @param restrict the component is secured
		 */
		private function scanProducerMethods(name:String, type:Type, modulePrefix:String, inConversation:Boolean, restrict:int):void {
			TypeScanner.scanProducerMethods(null, type,
				function(context:BaseContext, method:Method, annotation:Annotation):void {
					registerMethodProducer(method.returnType, name, method);
				}
			);
		}
		
		/**
		 * 	@private
		 * 	Internal implementation of producer methods annotation scanning
		 * 
		 *  @param name component name
		 * 	@param type bean type
		 *  @param modulePrefix current module prefix
		 *  @param inConversation the component is conversation scoped
		 *  @param restrict the component is secured
		 */
		private function scanProducerProperties(name:String, type:Type, modulePrefix:String, inConversation:Boolean, restrict:int):void {
			TypeScanner.scanProducerProperties(null, type,
				function(context:BaseContext, field:Field, annotation:Annotation):void {
					registerPropertyProducer(field.type, name, field);
				}
			);
		}
		
		/**
		 * 	@private
		 * 	Internal implementation of static injections
		 * 
		 *  @param properties factory object
		 * 	@param accs accessors/variables fragment of describeType
		 *  @param modulePrefix current module prefix
		 *  @param inConversation the component is conversation scoped
		 *  @param autoCreate the component is auto instantiated
		 *  @param restrict the component is secured
		 */
		private function scanPropertyInjections(properties:Object, type:Type, modulePrefix:String, inConversation:Boolean, restrict:int):void {
            for (var p:String in properties) {
                if (!(properties[p] is String) || !properties[p].match(/#{[^\.]*}/))
                    continue;
                
				var field:Field = type.getInstanceFieldNoCache(p);
				if (field != null && field.isWriteable() &&
					((!modulePrefix && !isComponent(p)) || (modulePrefix && !isComponent(modulePrefix + p)))) {
                	addComponentFromType(modulePrefix, p, field.type, 
                		false, inConversation, null,
                		null, Tide.RESTRICT_UNKNOWN
                	);
				}
            }
		}
		
		
		
		/**
		 * 	Unregister a Tide component and destroys all instances
		 * 
		 * 	@param name component name
		 */
		public function removeComponent(name:String):void {
		    if (isComponent(name) && getDescriptor(name).factory != null 
				&& getDescriptor(name).factory.type.getClass() === Subcontext)
		        return;
		    
		    _contextManager.destroyComponentInstances(name);
		    
		    removeComponentDescriptor(name);
		    
		    for (var eventType:String in _observersByType) {
		        var names:ArrayCollection = _observersByType[eventType] as ArrayCollection;
		        if (names != null) {
                    for (var i:int = 0; i < names.length; i++) {
                        if (names[i].name == name) {
                            names.removeItemAt(i);
                            i--;
                        }
                    }
        		    if (names.length == 0)
        		        delete _observersByType[eventType];
    		    }
		    }
		    
		    unregisterInjectionPoints(name);
		    	
		    unregisterProducer(name);
		}
		
		public function removeComponentDescriptor(name:String):void {
		    delete _componentDescriptors[name];
		}
				
		
		/**
		 * 	@private
		 * 	Returns a component descriptor
		 * 
		 *  @param name component name
		 *  @param create descriptor should be created if it does not exist 
		 * 
		 *  @return component descriptor
		 */
		public function getDescriptor(name:String, create:Boolean = true):ComponentDescriptor {
		    var descriptor:ComponentDescriptor = _componentDescriptors[name];
		    if (descriptor == null && create) {
		        descriptor = new ComponentDescriptor();
		        descriptor.name = name;
		        _componentDescriptors[name] = descriptor;
		    }
		    return descriptor;
		}
		
		/**
		 * 	Checks a name is a registered Tide component
		 * 
		 * 	@param name component name
		 *  
		 *  @return true if there is a component with this name
		 */
		public function isComponent(name:String):Boolean {
		    return getDescriptor(name, false) != null;
		}
		
		
		/**
		 *	@private
		 * 	Setup custom descriptor 
		 * 
		 *  @param componentName component name
		 *  @param descriptor component descriptor
		 */
		public function setupDescriptor(componentName:String, descriptor:ComponentDescriptor):void {
            if (descriptor.xmlDescriptor) {
				var type:Type = descriptor.factory.type;
				
                var observers:XMLList = descriptor.xmlDescriptor..Observer;
                for each (var observer:XML in observers) {
                    var eventTypes:String = observer.@eventType.toXMLString();
                    var eventTypeArray:Array = eventTypes.split(",");
                    var methodName:String = observer.@method.toXMLString();
                    var remote:Boolean = (observer.@remote.toXMLString() == "true");
                    var create:Boolean = !(observer.@create.toXMLString() == "false");
                    var localOnly:Boolean = (observer.@localOnly.toXMLString() == "true");
                    for each (var eventType:String in eventTypeArray) {
						var method:Method = type.getInstanceMethodNoCache(methodName);
						if (method != null) {
			        		if (eventType == null || StringUtil.trim(eventType).length == 0) {
								var params:Array = method.parameters;
								if (params.length != 1)
									throw new Error("Typed observer method should have one parameter: " + method.name);
			        			eventType = "$TideEvent$" + Parameter(params[0]).type.name;
							}
            	        	internalAddEventObserver(StringUtil.trim(eventType), componentName, method, remote, create, localOnly);
						}
                    }
                }

				var propName:String;
				var name:String;
				var f:Field;
				var modulePrefix:String = Tide.getModulePrefix(componentName);
				
                var injectors:XMLList = descriptor.xmlDescriptor..In;
                for each (var injector:XML in injectors) {
                    propName = injector.@property.toXMLString();
                    name = propName;
                    var sourcePropName:String = injector.@source.toXMLString();
                    if (sourcePropName.match(/#{.*}/))
                        continue;
                    
                    if (sourcePropName != null && sourcePropName.length > 0)
                        name = sourcePropName;
                    var autoCreate:String = injector.@create.toXMLString();
                    
                    if (!isComponent(name)) {
						f = type.getInstanceFieldNoCache(propName);
						if (f != null) {
                    		addComponentFromType(modulePrefix, name, f.type, 
                    			injector.@global == 'true', descriptor.scope == Tide.SCOPE_CONVERSATION, null, 
                    			autoCreate, Tide.RESTRICT_UNKNOWN
                    		);
						}
						else
							throw new Error("Field " + propName + " specified in In descriptor not found in type " + type.name);
					}
                }
                
                var outjectors:XMLList = descriptor.xmlDescriptor..Out;
                for each (var outjector:XML in outjectors) {
                    propName = outjector.@property.toXMLString();
                    name = propName;
                    var destPropName:String = outjector.@target.toXMLString();
                    
                    if (destPropName != null && destPropName.length > 0)
                        name = destPropName;
                    
                    if (!isComponent(name)) {
                    	name = modulePrefix + name;
						f = type.getInstanceFieldNoCache(propName);
						if (f != null) {
    	                	addComponentFromType(modulePrefix, name, f.type, 
    	                		outjector.@global == 'true', descriptor.scope == Tide.SCOPE_CONVERSATION, outjector.@remote.toXMLString(), 
    	                		null, Tide.RESTRICT_UNKNOWN
    	                	);
    	            	}
						else
							throw new Error("Field " + propName + " specified in Out descriptor not found in type " + type.name);
    	            }
                }
            }
     	}
     	
     	
     	/**
     	 * 	Return list of observers by event type
     	 *  
     	 *  @param type event type
     	 *  @return list of observer names
     	 */
     	public function getObserversByType(type:String):ArrayCollection { 
			return _observersByType[type];
		}
		
		
		/**
		 * 	Define if the component is defined as global (cannot be in a namespace/subcontext)
		 * 
		 *  @param name component name
		 *  @param global true if non component cannot be in a namespace/subcontext
		 */
		public function setComponentGlobal(name:String, global:Boolean):void {
		    getDescriptor(name).global = global;
		}
		
		/**
		 * 	Define the remote synchronization of the component
		 *  If NONE, the component state will never be sent to the server
		 * 
		 *  @param name component name
		 *  @param remoteSync true if the component should be remotely synchronized
		 */
		public function setComponentRemoteSync(name:String, remoteSync:int):void {
		    getDescriptor(name).remoteSync = remoteSync;
		}
	}
}
