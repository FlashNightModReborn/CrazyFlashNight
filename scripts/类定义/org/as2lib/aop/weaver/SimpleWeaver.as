/*
 * Copyright the original author or authors.
 * 
 * Licensed under the MOZILLA PUBLIC LICENSE, Version 1.1 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * 
 *      http://www.mozilla.org/MPL/MPL-1.1.html
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import org.as2lib.core.BasicClass;
import org.as2lib.aop.Weaver;
import org.as2lib.env.overload.Overload;
import org.as2lib.aop.Aspect;
import org.as2lib.env.reflect.PackageInfo;
import org.as2lib.env.reflect.ClassInfo;
import org.as2lib.env.reflect.PropertyInfo;
import org.as2lib.env.reflect.TypeMemberInfo;
import org.as2lib.aop.JoinPoint;
import org.as2lib.aop.joinpoint.MethodJoinPoint;
import org.as2lib.aop.joinpoint.GetPropertyJoinPoint;
import org.as2lib.aop.joinpoint.SetPropertyJoinPoint;
import org.as2lib.aop.Advice;
import org.as2lib.data.holder.map.HashMap;
import org.as2lib.data.holder.Map;
import org.as2lib.env.reflect.MethodInfo;
import org.as2lib.env.reflect.ConstructorInfo;
import org.as2lib.aop.joinpoint.ConstructorJoinPoint;
import org.as2lib.aop.joinpoint.AbstractJoinPoint;
import org.as2lib.util.ArrayUtil;

/**
 * {@code SimpleWeaver} is a simple implementation of the {@code Weaver} interface that
 * supports most needed functionalities.
 * 
 * @author Simon Wacker
 */
class org.as2lib.aop.weaver.SimpleWeaver extends BasicClass implements Weaver {
	
	/** Arrays of {@link Advice} instances that are mapped to affected {@link ClassInfo} instances. */
	private var advices:Map;
	
	/**
	 * Constructs a new {@code SimpleWeaver} instance.
	 */
	public function SimpleWeaver(Void) {
		advices = new HashMap();
	}
	
	/**
	 * Weaves the added aspects and advices into the affected types.
	 */
	public function weave(Void):Void {
		var affectedTypes:Array = advices.getKeys();
		for (var i:Number = 0; i < affectedTypes.length; i++) {
			var affectedType:ClassInfo = affectedTypes[i];
			var affectedAdvices:Array = advices.get(affectedType);
			if (affectedType) {
				weaveByTypeAndAdvices(affectedType, affectedAdvices);
			} else {
				weaveByPackageAndAdvices(PackageInfo.getRootPackage(), affectedAdvices);
			}
		}
	}
	
	private function weaveByPackageAndAdvices(package:PackageInfo, advices:Array):Void {
		if (package) {
			if (advices) {
				var classes:Array = package.getMemberClasses(false);
				if (classes) {
					for (var i:Number = 0; i < classes.length; i++) {
						var clazz:ClassInfo = ClassInfo(classes[i]);
						if (clazz) {
							weaveByTypeAndAdvices(clazz, advices);
						}
					}
				}
			}
		}
	}
	
	private function weaveByTypeAndAdvices(type:ClassInfo, advices:Array):Void {
		if (type) {
			var constructor:ConstructorInfo = type.getConstructor();
			if (constructor) {
				weaveByJoinPointAndAdvices(new ConstructorJoinPoint(constructor, null), advices);
			}
			var prototype:Object = type.getType().prototype;
			if (prototype.__constructor__) {
				// getType().valueOf() is important because valueOf ensures that not a proxy but the original constructor is used
				var superClassConstructor:ConstructorInfo = new ConstructorInfo(ClassInfo(type.getSuperType()), Function(type.getSuperType().getType().valueOf()));
				// there is a bug with the __constructor__ variable, we fix this by assigning
				// this variable by hand to the correct method
				prototype.__constructor__ = superClassConstructor.getMethod();
				if (this.advices.containsKey(superClassConstructor.getDeclaringType())) {
					weaveSuperClassConstructor(new ConstructorJoinPoint(superClassConstructor, null), prototype, this.advices.get(superClassConstructor.getDeclaringType()));
					//weaveBySuperClassConstructorJoinPointAndAdvices(, advices.get(superClassConstructor.getMethod()));
				}
			}
			var methods:Array = type.getMethodsByFlag(true);
			if (methods) {
				for (var i:Number = 0; i < methods.length; i++) {
					var method:MethodInfo = MethodInfo(methods[i]);
					if (method) {
						weaveByJoinPointAndAdvices(new MethodJoinPoint(method, null), advices);
					}
				}
			}
			var properties:Array = type.getPropertiesByFlag(true);
			if (properties) {
				for (var i:Number = 0; i < properties.length; i++) {
					var property:PropertyInfo = PropertyInfo(properties[i]);
					if (property) {
						weaveByJoinPointAndAdvices(new GetPropertyJoinPoint(property, null), advices);
						weaveByJoinPointAndAdvices(new SetPropertyJoinPoint(property, null), advices);
					}
				}
			}
		}
	}
	
	private function weaveSuperClassConstructor(superClassConstructorJoinPoint:ConstructorJoinPoint, prototype, advices:Array):Void {
		if (prototype && advices) {
			for (var i:Number = 0; i < advices.length; i++) {
				var advice:Advice = Advice(advices[i]);
				if (advice) {
					if (advice.captures(superClassConstructorJoinPoint)) {
						// TODO refactor
						// not ' = snapshot()' because this makes a snapshot of the constructor in the package and not in the prototype
						var c:ConstructorInfo = new ConstructorInfo(ClassInfo(superClassConstructorJoinPoint.getInfo().getDeclaringType()), prototype.__constructor__);
						prototype.__constructor__ = advice.getProxy(new ConstructorJoinPoint(c, null));
					}
				}
			}
		}
	}
	
	private function weaveByJoinPointAndAdvices(joinPoint:JoinPoint, advices:Array):Void {
		if (joinPoint) {
			if (advices) {
				for (var i:Number = 0; i < advices.length; i++) {
					var advice:Advice = Advice(advices[i]);
					if (advice) {
						if (advice.captures(joinPoint)) {
							weaveByJoinPointAndAdvice(joinPoint.snapshot(), advice);
						}
					}
				}
			}
		}
	}
	
	private function weaveByJoinPointAndAdvice(joinPoint:JoinPoint, advice:Advice):Void {
		var proxy:Function = advice.getProxy(joinPoint);
		var info:TypeMemberInfo = joinPoint.getInfo();
		if (joinPoint.getType() == AbstractJoinPoint.CONSTRUCTOR) {
			info.getDeclaringType().getPackage().getPackage()[info.getDeclaringType().getName()] = proxy;
		} else {
			if (info.isStatic()) {
				info.getDeclaringType().getType()[info.getName()] = proxy;
			} else {
				info.getDeclaringType().getType().prototype[info.getName()] = proxy;
			}
		}
	}
	
	/**
	 * @overload #addAspectForAllTypes
	 * @overload #addAspectForAllTypesInPackage
	 * @overload #addAspectForMultipleAffectedTypes
	 * @overload #addAspectForOneAffectedType
	 */
	public function addAspect():Void {
		var o:Overload = new Overload(this);
		o.addHandler([Aspect], addAspectForAllTypes);
		o.addHandler([Aspect, Object], addAspectForAllTypesInPackage);
		o.addHandler([Aspect, Array], addAspectForMultipleAffectedTypes);
		o.addHandler([Aspect, Function], addAspectForOneAffectedType);
		o.forward(arguments);
	}
	
	/**
	 * Adds the given {@code aspect} for all types. This means that all types are
	 * searched through starting from the default or root package and checked whether
	 * their join points match any of the advices of the {@code aspect}.
	 * 
	 * @param aspect the aspect whose advices shall be woven-into captured join points
	 */
	public function addAspectForAllTypes(aspect:Aspect):Void {
		if (aspect) {
			addAspectForAllTypesInPackage(aspect, PackageInfo.getRootPackage());
		}
	}
	
	/**
	 * Adds the given {@code aspect} for the types that are directly members of the
	 * given {@code affectedPackage} or any sub-package. All these types are regarded
	 * as affected types that are searched through for matching join points.
	 * 
	 * @param aspect the aspect whose advices shall be woven-into captured join points
	 * @param affectedPackage the package to search for matching join points
	 * @throws IllegalArgumentException if {@code affectedPackage} is {@code null} or
	 * {@code undefined}
	 */
	public function addAspectForAllTypesInPackage(aspect:Aspect, affectedPackage:Object):Void {
		if (aspect) {
			if (affectedPackage !== null && affectedPackage !== undefined) {
				var packageInfo:PackageInfo = PackageInfo.forPackage(affectedPackage);
				if (packageInfo) {
					var classes:Array = packageInfo.getMemberClasses(false);
					for (var i:Number = 0; i < classes.length; i++) {
						var clazz:ClassInfo = ClassInfo(classes[i]);
						if (clazz) {
							addAspectForOneAffectedType(aspect, clazz.getType());
						}
					}
				}
			}
		}
	}
	
	/**
	 * Adds the given {@code aspect} for the types that are contained in
	 * {@code affectedTypes}. The {@code affectedTypes} array is supposed to hold
	 * elements of type {@code Function}.
	 * 
	 * @param aspect the aspect whose advices shall be woven-into captured join points
	 * @param affectedType a list of affected types
	 */
	public function addAspectForMultipleAffectedTypes(aspect:Aspect, affectedTypes:Array):Void {
		if (aspect) {
			if (affectedTypes) {
				for (var i:Number = 0; i < affectedTypes.length; i++) {
					var affectedType:Function = Function(affectedTypes[i]);
					if (affectedType) {
						addAspectForOneAffectedType(aspect, affectedType);
					}
				}
			}
		}
	}
	
	/**
	 * Adds the given {@code aspect} for the given {@code affectedType}. Only the given
	 * {@code affectedType} is searched through when searching for join points that may
	 * match the advices of the given {@code aspect}.
	 * 
	 * @param aspect the aspect whose advices shall be woven-into captured join points
	 * @param affectedType the affected type to search for join points
	 */
	public function addAspectForOneAffectedType(aspect:Aspect, affectedType:Function):Void {
		if (aspect) {
			if (affectedType) {
				var advices:Array = aspect.getAdvices();
				if (advices) {
					for (var i:Number = 0; i < advices.length; i++) {
						var advice:Advice = Advice(advices[i]);
						if (advice) {
							addAdviceForOneAffectedType(advice, affectedType);
						}
					}
				}
			}
		}
	}
	
	/**
	 * @overload #addAdviceForAllTypes
	 * @overload #addAdviceForAllTypesInPackage
	 * @overload #addAdviceForMultipleAffectedTypes
	 * @overload #addAdviceForOneAffectedType
	 */
	public function addAdvice():Void {
		var o:Overload = new Overload(this);
		o.addHandler([Advice], addAdviceForAllTypes);
		o.addHandler([Advice, Object], addAdviceForAllTypesInPackage);
		o.addHandler([Advice, Array], addAdviceForMultipleAffectedTypes);
		o.addHandler([Advice, Function], addAdviceForOneAffectedType);
		o.forward(arguments);
	}
	
	/**
	 * Adds the given {@code advice} for all types. This means that all types are
	 * searched through starting from the default or root package and checked whether
	 * their join points match any of the advices of the {@code advice}.
	 * 
	 * @param advice the advice to weave-into matching join points
	 */
	public function addAdviceForAllTypes(advice:Advice):Void {
		if (advice) {
			addAdviceForAllTypesInPackage(advice, PackageInfo.getRootPackage());
		}
	}
	
	/**
	 * Adds the given {@code advice} for the types that are directly members of the
	 * given {@code affectedPackage} or any sub-package. All these types are regarded
	 * as affected types that are searched through for matching join points.
	 * 
	 * @param advice the advice to weave-into captured join points
	 * @param affectedPackage the package to search for matching join points
	 */
	public function addAdviceForAllTypesInPackage(advice:Advice, package:Object):Void {
		if (advice) {
			if (package !== null && package !== undefined) {
				var packageInfo:PackageInfo = PackageInfo.forPackage(package);
				if (packageInfo) {
					var classes:Array = packageInfo.getMemberClasses(false);
					for (var i:Number = 0; i < classes.length; i++) {
						var clazz:ClassInfo = ClassInfo(classes[i]);
						if (clazz) {
							addAdviceForOneAffectedType(advice, clazz.getType());
						}
					}
				}
			}
		}
	}
	
	/**
	 * Adds the given {@code advice} for the types that are contained in
	 * {@code affectedTypes}. The {@code affectedTypes} array is supposed to hold
	 * elements of type {@code Function}.
	 * 
	 * @param advice the advice to weave-into captured join points
	 * @param affectedType a list of affected types
	 */
	public function addAdviceForMultipleAffectedTypes(advice:Advice, affectedTypes:Array):Void {
		if (advice) {
			if (affectedTypes) {
				for (var i:Number = 0; i < affectedTypes.length; i++) {
					var affectedType:Function = Function(affectedTypes[i]);
					if (affectedType) {
						addAdviceForOneAffectedType(advice, affectedType);
					}
				}
			}
		}
	}
	
	/**
	 * Adds the given {@code advice} for the given {@code affectedType}. Only the given
	 * {@code affectedType} is searched through when searching for join points that may
	 * match the given {@code advice}.
	 * 
	 * @param advice the advice to weave-into captured join points
	 * @param affectedType the affected type to search for join points
	 */
	public function addAdviceForOneAffectedType(advice:Advice, affectedType:Function):Void {
		if (advice) {
			var typeInfo:ClassInfo = null;
			if (affectedType) {
				typeInfo = ClassInfo.forClass(affectedType);
			}
			if (!advices.containsKey(typeInfo)) {
				advices.put(typeInfo, new Array());
			}
			var affectedAdvices:Array = advices.get(typeInfo);
			// TODO is this really always wanted? add a flag if not?
			if (!ArrayUtil.contains(affectedAdvices, advice)) {
				affectedAdvices.push(advice);
			}
			if (typeInfo.getSuperType()) {
				addAdviceForOneAffectedType(advice, typeInfo.getSuperType().getType());
			}
		}
	}
	
}