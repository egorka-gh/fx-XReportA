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
package org.granite.validation.helper {

	/**
	 * Helper class used for declaring constraint annotation argument types. See
	 * standard constraint implementations for usage.
	 * 
	 * @author Franck WOLFF
	 * 
	 * @see ConstraintHelper
	 */
	public class ParameterDefinition {

		private var _name:String;
		private var _type:Class;
		private var _defaultValue:*;
		private var _optional:Boolean;
		private var _array:Boolean;
		private var _aliases:Array;
		
		function ParameterDefinition(name:String,
									 type:Class,
									 defaultValue:*,
									 optional:Boolean,
									 array:Boolean = false,
									 aliases:Array = null) {
			if (name == null || type == null)
				throw new ArgumentError("name and type cannot be null");
			_name = name;
			_type = type;
			_defaultValue = defaultValue;
			_optional = optional;
			_array = array;
			_aliases = aliases;
		}
		
		public function get name():String {
			return _name;
		}
		
		public function get type():Class {
			return _type;
		}
		
		public function get defaultValue():* {
			return _defaultValue;
		}
		
		public function get optional():Boolean {
			return _optional;
		}
		
		public function get array():Boolean {
			return _array;
		}
		
		public function get aliases():Array {
			return _aliases;
		}
		
		public function getAlias(value:String):String {
			if (_aliases == null || _aliases.length == 0)
				return value;
			var i:int = _aliases.indexOf(value);
			if (i == -1 || (i % 2) != 0)
				return value;
			return _aliases[i+1];
		}
	}
}