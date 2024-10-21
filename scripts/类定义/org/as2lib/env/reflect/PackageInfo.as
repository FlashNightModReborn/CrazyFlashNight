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
import org.as2lib.env.overload.Overload;
import org.as2lib.env.except.IllegalArgumentException;
import org.as2lib.env.reflect.ReflectConfig;
import org.as2lib.env.reflect.ClassInfo;
import org.as2lib.env.reflect.PackageMemberInfo;
import org.as2lib.env.reflect.PackageMemberFilter;
import org.as2lib.env.reflect.algorithm.PackageAlgorithm;
import org.as2lib.env.reflect.algorithm.PackageMemberAlgorithm;
import org.as2lib.util.StringUtil;

/**
 * {@code PackageInfo} represents a real package in the Flash environment. This class
 * is used to get specific information about the package it represents.
 *
 * <p>You can use the static search methods {@link #forName} and {@link #forPackage} to
 * get package infos for specific packages.
 *
 * <p>If you for example have a package you wanna get information about you first must
 * retrieve the appropriate {@code PackageInfo} instance and you can then use its
 * methods to get the wanted information.
 * 
 * <code>
 *   var packageInfo:PackageInfo = PackageInfo.forPackage(org.as2lib.core);
 *   trace("Package full name: " + packageInfo.getFullName());
 *   trace("Parent package name: " + packageInfo.getParent().getName());
 *   trace("Member classes: " + packageInfo.getMemberClasses());
 *   trace("Member packages: " + packageInfo.getMemberPackages());
 * </code>
 *
 * @author Simon Wacker
 */
class org.as2lib.env.reflect.PackageInfo extends BasicClass implements PackageMemberInfo {
	
	/** The algorithm to find packages. */
	private static var packageAlgorithm:PackageAlgorithm;
	
	/** The algorithm to find members of packages, that are classes and packages. */
	private static var packageMemberAlgorithm:PackageMemberAlgorithm;
	
	/** Stores the root package of the package hierarchy. */
	private static var rootPackage:PackageInfo;
	
	/**
	 * Returns the package info corresponding to the passed-in {@code packageName}.
	 *
	 * <p>The passed-in {@code packageName} must be composed of the preceding path and
	 * the actual package name, that means it must be fully qualified. For example
	 * {@code "org.as2lib.core"}.
	 *
	 * <p>This method first checks whether the package is already contained in the
	 * cache.
	 *
	 * @param packageName the fully qualified name of the package to find
	 * @return the package info corresponding to the passed-in {@code packageName}
	 * @throws IllegalArgumentException if the passed-in {@code packageName} is {@code null},
	 * {@code undefined} or an empty string or if the object corresponding to the passed-in
	 * {@code packageName} is not of type {@code "object"}
	 * @throws PackageNotFoundException if a package with the passed-in {@code packageName}
	 * could not be found
	 */
	public static function forName(packageName:String):PackageInfo {
		return getPackageAlgorithm().executeByName(packageName);
	}
	
	/**
	 * Returns the package info corresponding to the passed-in {@code package}.
	 *
	 * <p>This method first checks whether the package info is already contained in the
	 * cache.
	 *
	 * @param package the package you wanna get the package info for
	 * @return the package info corresponding to the passed-in {@code package}
	 * @throws IllegalArgumentException if the passed-in {@code package} is {@code null}
	 * or {@code undefined}
	 */
	public static function forPackage(package):PackageInfo {
		// _global == null results in true, as well does _global == undefined because of that === is used
		if (package === null || package === undefined) {
			throw new IllegalArgumentException("Argument 'package' [" + package + "] must not be 'null' nor 'undefined'.", eval("th" + "is"), arguments);
		}
		var packageInfo:PackageInfo = ReflectConfig.getCache().getPackage(package);
		if (packageInfo) return packageInfo;
		return ReflectConfig.getCache().addPackage(new PackageInfo(package));
	}
	
	/**
	 * Sets the algorithm used to find packages.
	 *
	 * <p>If {@code newPackageAlgorithm} is {@code null} or {@code undefined},
	 * {@link #getPackageAlgorithm} will return the default package algorithm.
	 *
	 * @param newPackageAlgorithm the new algorithm to find packages
	 * @see #getPackageAlgorithm
	 */
	public static function setPackageAlgorithm(newPackageAlgorithm:PackageAlgorithm):Void {
		packageAlgorithm = newPackageAlgorithm;
	}
	
	/**
	 * Returns the algorithm used to find packages.
	 *
	 * <p>Either the algorithm set via {@link #setPackageAlgorithm} method will be
	 * returned or the default one which is an instance of class {@link PackageAlgorithm}.
	 *
	 * @return the set or the default package algorithm
	 * @see #setPackageAlgorithm
	 */
	public static function getPackageAlgorithm(Void):PackageAlgorithm {
		if (!packageAlgorithm) packageAlgorithm = new PackageAlgorithm();
		return packageAlgorithm;
	}
	
	/**
	 * Sets the algorithm used to find members of packages.
	 *
	 * <p>Members of packages are classes, interfaces and packages.
	 *
	 * <p>If {@code newPackageMemberAlgorithm} is {@code null} or {@code undefined},
	 * {@link #getPackageMemberAlgorithm} will return the default package member
	 * algorithm.
	 *
	 * @param newPackageMemberAlgorithm the new algorithm to find members of packages
	 * @see #getPackageMemberAlgorithm
	 */
	public static function setPackageMemberAlgorithm(newPackageMemberAlgorithm:PackageMemberAlgorithm):Void {
		packageMemberAlgorithm = newPackageMemberAlgorithm;
	}
	
	/**
	 * Returns the member algorithm used to find members of packages.
	 *
	 * <p>Either the algorithm set via {@link #setPackageMemberAlgorithm} will be
	 * returned or the default one which is an instance of class {@link PackageMemberAlgorithm}.
	 *
	 * @return the set or the default member algorithm
	 * @see #setPackageMemberAlgorithm
	 */
	public static function getPackageMemberAlgorithm(Void):PackageMemberAlgorithm {
		if (!packageMemberAlgorithm) packageMemberAlgorithm = new PackageMemberAlgorithm();
		return packageMemberAlgorithm;
	}
	
	/**
	 * Returns the root package of the package hierarchy.
	 *
	 * <p>If you do not set a custom root package via the {@code #setRootPackage}
	 * method, the default root package is returned that refers to {@code _global}.
	 *
	 * @return the root package of the package hierarchy.
	 * @see #setRootPackage
	 */
	public static function getRootPackage(Void):PackageInfo {
		if (!rootPackage) rootPackage = new PackageInfo(_global, "_global", null);
		return rootPackage;
	}
	
	/**
	 * Sets the new root package of the package hierarchy.
	 *
	 * <p>If the passed-in {@code newRootPackage} argument is {@code null} or
	 * {@code undefined} the {@code #getRootPackage} method will return the default
	 * root package.
	 *
	 * @param newRootPackage the new root package of the package hierarchy
	 * @see #getRootPackage
	 */
	public static function setRootPackage(newRootPackage:PackageInfo):Void {
		rootPackage = newRootPackage;
	}
	
	/** The name of this package. */
	private var name:String;
	
	/** The fully qualified name of this package. */
	private var fullName:String;
	
	/** The actual package this instance represents. */
	private var package;
	
	/** The parent of this package. */
	private var parent:PackageInfo;
	
	/** The members of this package. */
	private var members:Array;
	
	/**
	 * Constructs a new {@code PackageInfo} instance.
	 *
	 * <p>Note that you do not have to pass-in the concrete {@code package}. But if you
	 * do not pass it in some methods cannot do their job correctly.
	 * 
	 * <p>If you do not pass-in the {@code name} or the {@code parent} they are resolved
	 * lazily when requested using the passed-in {@code package}.
	 *
	 * @param package the actual package this instance represents
	 * @param name (optional) the name of the package
	 * @param parent (optional) the parent package
	 */
	public function PackageInfo(package,
								name:String,  
							  	parent:PackageInfo) {
		this.package = package;
		this.name = name;
		this.parent = parent;
	}
	
	/**
	 * Returns the name of the represented package.
	 *
	 * <p>This does not include the package's path/namespace. If this package info
	 * represented for example the {@code org.as2lib.core} package the returned
	 * name would be {@code "core"}.
	 *
	 * @return the name of the represented package
	 * @see #getFullName
	 */
	public function getName(Void):String {
		if (name === undefined) initNameAndParent();
		return name;
	}
	
	/**
	 * Returns the fully qualified name of the represented package. This means the name
	 * of the package plus its package path/namespace.
	 *
	 * <p>The path is not included if:
	 * <ul>
	 *   <li>The {@link #getParent} method returns {@code null} or {@code undefined}.</li>
	 *   <li>
	 *     The {@link #getParent} method returns the root package, that means its 
	 *     {@link #isRoot} method returns {@code true}.
	 *   </li>
	 * </ul>
	 *
	 * @return the fully qualified name of the package
	 */
	public function getFullName(Void):String {
		if (fullName === undefined) {
			if (getParent().isRoot() || isRoot()) {
				return (fullName = getName());
			}
			fullName = getParent().getFullName() + "." + getName();
		}
		return fullName;
	}
	
	/**
	 * Returns the actual package this instance represents.
	 *
	 * @return the actual package
	 */
	public function getPackage(Void) {
		return package;
	}
	
	/**
	 * Returns the parent of the represented package.
	 *
	 * <p>The parent is the package the represented package is contained in / a member
	 * of. The parent of the package {@code org.as2lib.core} is {@code org.as2lib}.
	 *
	 * @return the parent of the represented package
	 */
	public function getParent(Void):PackageInfo {
		if (parent === undefined) initNameAndParent();
		return parent;
	}
	
	/**
	 * Initializes the name and the parent of the represented package.
	 *
	 * <p>This is done using the result of an execution of the package algorithm
	 * returned by the static {@link #getPackageAlgorithm} method.
	 */
	private function initNameAndParent(Void):Void {
		var info = getPackageAlgorithm().execute(getPackage());
		if (name === undefined) name = info.name == null ? null : info.name;
		if (parent === undefined) parent = info.parent == null ? null : info.parent;
	}
	
	/**
	 * @overload #getMembersByFlag
	 * @overload #getMembersByFilter
	 */
	public function getMembers():Array {
		var o:Overload = new Overload(this);
		o.addHandler([], getMembersByFlag);
		o.addHandler([Boolean], getMembersByFlag);
		o.addHandler([PackageMemberFilter], getMembersByFilter);
		return o.forward(arguments);
	}
	
	/**
	 * Returns an array containing {@link PackageMemberInfo} instances representing the
	 * members of the package and maybe the ones of the sub-packages.
	 *
	 * <p>The members of the package are all types and packages contained in the
	 * represented package.
	 *
	 * <p>If {@code filterSubPackages} is {@code null} or {@code undefined} it is
	 * interpreted as {@code true}, that means sub-packages' package members will be
	 * filtered/excluded from the result by default.
	 *
	 * <p>{@code null} will be returned if
	 * <ul>
	 *   <li>The {@link #getPackage} method returns {@code null} or {@code undefined}.</li>
	 *   <li>
	 *     The {@code execute} method of the algorithm returned by
	 *     {@link #getPackageMemberAlgorithm} returns {@code null} or {@code undefined}.
	 *   </li>
	 * </ul>
	 *
	 * @param filterSubPackages (optional) determines whether to filter the sub-packages'
	 * members
	 * @return an array containing the members of the represented package
	 */
	public function getMembersByFlag(filterSubPackages:Boolean):Array {
		// not just "== null" because "_global == null" evaluates to "true"
		if (getPackage() === null || getPackage() === undefined) return null;
		if (filterSubPackages == null) filterSubPackages = true;
		if (members === undefined) {
			members = getPackageMemberAlgorithm().execute(this);
		}
		var result:Array = members.concat();
		if (!filterSubPackages) {
			var subPackages:Array = members["packages"];
			for (var i:Number = 0; i < subPackages.length; i++) {
				result = result.concat(PackageInfo(subPackages[i]).getMembersByFlag(filterSubPackages));
			}
		}
		return result;
	}
	
	/**
	 * Returns an array containing {@link PackageMemberInfo} instances representing the
	 * members of the package and sub-packages that are not filtered/excluded.
	 *
	 * <p>The members of this package are all types and packages contained in the
	 * represented package.
	 *
	 * <p>The {@link PackageMemberFilter#filter} method of the passed-in {@code packageMemberFilter}
	 * is invoked for every package member to determine whether it shall be contained
	 * in the result.
	 *
	 * <p>If the passed-in {@code packageMemberFilter} is {@code null} or {@code undefined}
	 * the result of the invocation of {@link #getMembersByFlag} with argument {@code true}
	 * will be returned.
	 *
	 * <p>{@code null} will be returned if:
	 * <ul>
	 *   <li>The {@link #getPackage} method returns {@code null} or {@code undefined}.</li>
	 *   <li>
	 *     The {@code execute} method of the algorithm returned by
	 *     {@link #getPackageMemberAlgorithm} returns {@code null} or {@code undefined}.
	 *   </li>
	 * </ul>
	 *
	 * @param packageMemberFilter the filter that filters unwanted package members out
	 * @return an array containing the remaining members of the represented package
	 */
	 public function getMembersByFilter(packageMemberFilter:PackageMemberFilter):Array {
		// not just "== null" because "_global == null" evaluates to "true"
		if (getPackage() === null || getPackage() === undefined) return null;
		if (!packageMemberFilter) return getMembersByFlag(true);
		var result:Array = getMembersByFlag(packageMemberFilter.filterSubPackages());
		for (var i:Number = 0; i < result.length; i++) {
			if (packageMemberFilter.filter(PackageMemberInfo(result[i]))) {
				result.splice(i, 1);
				i--;
			}
		}
		return result;
	}
	
	/**
	 * @overload #getMemberClassesByFlag
	 * @overload #getMemberClassesByFilter
	 */
	public function getMemberClasses():Array {
		var o:Overload = new Overload(this);
		o.addHandler([], getMemberClassesByFlag);
		o.addHandler([Boolean], getMemberClassesByFlag);
		o.addHandler([PackageMemberFilter], getMemberClassesByFilter);
		return o.forward(arguments);
	}
	
	/**
	 * Returns an array containing {@link ClassInfo} instances representing the member
	 * classes of the package and maybe the ones of the sub-packages.
	 *
	 * <p>If {@code filterSubPackages} is {@code null} or {@code undefined} it is
	 * interpreted as {@code true}, this means that sub-packages' classes are filtered
	 * by default.
	 *
	 * <p>{@code null} will be returned if:
	 * <ul>
	 *   <li>The {@link #getPackage} method returns {@code null} or {@code undefined}.</li>
	 *   <li>
	 *     The {@code execute} method of the algorithm returned by
	 *     {@link #getPackageMemberAlgorithm} returns {@code null} or {@code undefined}.
	 *   </li>
	 * </ul>
	 *
	 * @param filterSubPackages (optional) determines whether to filter/exclude the
	 * sub-packages' member classes
	 * @return an array containing the member classes of the represented package
	 */
	public function getMemberClassesByFlag(filterSubPackages:Boolean):Array {
		// not just "== null" because "_global == null" evaluates to "true"
		if (getPackage() === null || getPackage() === undefined) return null;
		if (filterSubPackages == null) filterSubPackages = true;
		if (members === undefined) {
			members = getPackageMemberAlgorithm().execute(this);
		}
		var result:Array = members["classes"].concat();
		if (!filterSubPackages) {
			var subPackages:Array = members["packages"];
			for (var i:Number = 0; i < subPackages.length; i++) {
				result = result.concat(PackageInfo(subPackages[i]).getMemberClassesByFlag(filterSubPackages));
			}
		}
		return result;
	}
	
	/**
	 * Returns an array containing {@link ClassInfo} instances representing the class
	 * members of the package and sub-packages that are not filtered/excluded.
	 *
	 * <p>The {@link PackageMemberFilter#filter} method of the passed-in {@code classFilter}
	 * is invoked for every member class to determine whether it shall be contained in
	 * the result.
	 *
	 * <p>If the passed-in {@code clasFilter} is {@code null} or {@code undefined} the
	 * result of an invocation of {@link #getMemberClassesByFlag} with argument {@code true}
	 * will be returned.
	 *
	 * <p>{@code null} will be returned if:
	 * <ul>
	 *   <li>The {@link #getPackage} method returns {@code null} or {@code undefined}.</li>
	 *   <li>
	 *     The {@code execute} method of the algorithm returned by
	 *     {@link #getPackageMemberAlgorithm} returns {@code null} or {@code undefined}.
	 *   </li>
	 * </ul>
	 *
	 * @param classFilter the filter that filters unwanted member classes out
	 * @return an array containing the remaining member classes of the represented
	 * package
	 */
	 public function getMemberClassesByFilter(classFilter:PackageMemberFilter):Array {
		// not just "== null" because "_global == null" evaluates to "true"
		if (getPackage() === null || getPackage() === undefined) return null;
		if (!classFilter) return getMemberClassesByFlag(true);
		var result:Array = getMemberClassesByFlag(classFilter.filterSubPackages());
		for (var i:Number = 0; i < result.length; i++) {
			if (classFilter.filter(ClassInfo(result[i]))) {
				result.splice(i, 1);
				i--;
			}
		}
		return result;
	}
	
	/**
	 * @overload #getMemberPackagesByFlag
	 * @overload #getMemberPackagesByFilter
	 */
	public function getMemberPackages():Array {
		var o:Overload = new Overload(this);
		o.addHandler([], getMemberPackagesByFlag);
		o.addHandler([Boolean], getMemberPackagesByFlag);
		o.addHandler([PackageMemberFilter], getMemberPackagesByFilter);
		return o.forward(arguments);
	}
	
	/**
	 * Returns an array containing {@link PackageInfo} instances representing the member
	 * packages of the package and maybe the ones of the sub-packages.
	 *
	 * <p>If {@code filterSubPackages} is {@code null} or {@code undefined} it is
	 * interpreted as {@code true}, this means sub-packages' packages are filtered
	 * by default.
	 *
	 * <p>{@code null} will be returned if:
	 * <ul>
	 *   <li>The {@link #getPackage} method returns {@code null} or {@code undefined}.</li>
	 *   <li>
	 *     The {@code execute} method of the algorithm returned by
	 *     {@link #getPackageMemberAlgorithm} returns {@code null} or {@code undefined}.
	 *   </li>
	 * </ul>
	 *
	 * @param filterSubPackages (optional) determines whether the sub-packages' member
	 * packages shall be filtered/excluded from or included in the result
	 * @return an array containing the member packages of the represented package
	 */
	public function getMemberPackagesByFlag(filterSubPackages:Boolean):Array {
		// not just "== null" because "_global == null" evaluates to "true"
		if (getPackage() === null || getPackage() === undefined) return null;
		if (filterSubPackages == null) filterSubPackages = true;
		if (members === undefined) {
			members = getPackageMemberAlgorithm().execute(this);
		}
		var result:Array = members["packages"].concat();
		if (!filterSubPackages) {
			var subPackages:Array = members["packages"];
			for (var i:Number = 0; i < subPackages.length; i++) {
				result = result.concat(PackageInfo(subPackages[i]).getMemberPackagesByFlag(filterSubPackages));
			}
		}
		return result;
	}
	
	/**
	 * Returns an array containing {@link PackageInfo} instances representing the
	 * package members of the package and sub-packages that are not filtered/excluded.
	 *
	 * <p>The {@link PackageMemberFilter#filter} method of the passed-in {@code packageFilter}
	 * is invoked for every member package to determine whether it shall be contained
	 * in the result.
	 *
	 * <p>If the passed-in {@code packageFilter} is {@code null} or {@code undefined}
	 * the result of the invocation of {@link #getMemberPackagesByFlag} with argument
	 * {@code true} will be returned.
	 *
	 * <p>{@code null} will be returned if:
	 * <ul>
	 *   <li>The {@link #getPackage} method returns {@code null} or {@code undefined}.</li>
	 *   <li>
	 *     The {@code execute} method of the algorithm returned by
	 *     {@link #getPackageMemberAlgorithm} returns {@code null} or {@code undefined}.
	 *   </li>
	 * </ul>
	 *
	 * @param packageFilter the filter that filters unwanted member packages out
	 * @return an array containing the remaining member packages of the represented
	 * package
	 */
	 public function getMemberPackagesByFilter(packageFilter:PackageMemberFilter):Array {
		// not just "== null" because "_global == null" evaluates to "true"
		if (getPackage() === null || getPackage() === undefined) return null;
		if (!packageFilter) return getMemberPackagesByFlag(true);
		var result:Array = getMemberPackagesByFlag(packageFilter.filterSubPackages());
		for (var i:Number = 0; i < result.length; i++) {
			if (packageFilter.filter(PackageInfo(result[i]))) {
				result.splice(i, 1);
				i--;
			}
		}
		return result;
	}
	
	/**
	 * @overload #getMemberByName
	 * @overload #getMemberByMember
	 */
	public function getMember():PackageMemberInfo {
		var o:Overload = new Overload(this);
		o.addHandler([String], getMemberByName);
		o.addHandler([Object], getMemberByMember);
		return o.forward(arguments);
	}
	
	/**
	 * Returns the package member info corresponding to the passed-in {@code memberName}.
	 *
	 * <p>If the package member with the passed-in {@code memberName} cannot be found
	 * directly in the represented package its sub-packages are searched through.
	 *
	 * <p>{@code null} will be returned if:
	 * <ul>
	 *   <li>The {@link #getMembers} method returns {@code null} or {@code undefined}.</li>
	 *   <li>The passed-in {@code memberName} is {@code null} or {@code undefined}.</li>
	 *   <li>There is no member with the passed-in {@code memberName}.</li>
	 * </ul>
	 *
	 * @param memberName the name of the member to return
	 * @return the member corresponding to the passed-in {@code memberName}
	 */
	public function getMemberByName(memberName:String):PackageMemberInfo {
		if (memberName == null) return null;
		if (getMembersByFlag(true)) {
			if (members[memberName]) return members[memberName];
			var subPackages:Array = members["packages"];
			for (var i:Number = 0; i < subPackages.length; i++) {
				var member:PackageMemberInfo = PackageInfo(subPackages[i]).getMemberByName(memberName);
				if (member) return member;
			}
		}
		return null;
	}
	
	/**
	 * Returns the package member info corresponding to the passed-in
	 * {@code concreteMember}.
	 *
	 * <p>If the package member corresponding to the passed-in {@code concreteMember}
	 * cannot be found directly in the represented package its sub-packages are
	 * searched through.
	 *
	 * <p>{@code null} will be returned if:
	 * <ul>
	 *   <li>The {@link #getMembers} method returns {@code null} or {@code undefined}.</li>
	 *   <li>The passed-in {@code concreteMember} is {@code null} or {@code undefined}.</li>
	 *   <li>The member could not be found.</li>
	 * </ul>
	 *
	 * @param concreteMember the concrete member to find
	 * @return the package member info instance corresponding to the {@code concreteMember}
	 */
	public function getMemberByMember(concreteMember):PackageMemberInfo {
		if (concreteMember == null) return null;
		if (typeof(concreteMember) == "function") {
			return getMemberClassByClass(concreteMember);
		} else {
			return getMemberPackageByPackage(concreteMember);
		}
	}
	
	/**
	 * @overload #getMemberClassByName
	 * @overload #getMemberClassByClass
	 */
	public function getMemberClass(clazz):ClassInfo {
		var o:Overload = new Overload(this);
		o.addHandler([String], getMemberClassByName);
		o.addHandler([Function], getMemberClassByClass);
		return o.forward(arguments);
	}
	
	/**
	 * Returns the class info corresponding to the passed-in {@code className}.
	 *
	 * <p>If the member class with the passed-in {@code className} cannot be found
	 * directly in the represented package its sub-packages are searched through.
	 *
	 * <p>{@code null} will be returned if:
	 * <ul>
	 *   <li>The passed-in {@code className} is {@code null} or {@code undefined}.</li>
	 *   <li>There is no class with the passed-in {@code className}.</li>
	 * </ul>
	 *
	 * @param className the name of the class
	 * @return the class info corresponding to the passed-in {@code className}
	 */
	public function getMemberClassByName(className:String):ClassInfo {
		if (className == null) return null;
		if (getMemberClassesByFlag(true)) {
			if (members["classes"][className]) return members["classes"][className];
		}
		var subPackages:Array = getMemberPackagesByFlag(true);
		if (subPackages) {
			for (var i:Number = 0; i < subPackages.length; i++) {
				var clazz:ClassInfo = PackageInfo(subPackages[i]).getMemberClassByName(className);
				if (clazz) return clazz;
			}
		}
		return null;
	}
	
	/**
	 * Returns the class info corresponding to the passed-in {@code concreteClass}.
	 *
	 * <p>If the member class corresponding to the passed-in {@code concreteClass}
	 * cannot be found directly in the represented package its sub-packages are
	 * searched through.
	 *
	 * <p>{@code null} will be returned if:
	 * <ul>
	 *   <li>The passed-in {@code concreteClass} is {@code null} or {@code undefined}.</li>
	 *   <li>
	 *     There is no class matching the passed-in {@code concreteClass} in this
	 *     package or any sub-packages.</li>
	 * </ul>
	 *
	 * @param concreteClass the concrete class a corresponding class info shall be
	 * returned
	 * @return the class info corresponding to the passed-in {@code concreteClass}
	 */
	public function getMemberClassByClass(concreteClass:Function):ClassInfo {
		if (!concreteClass) return null;
		var classes:Array = getMemberClassesByFlag(true);
		if (classes) {
			for (var i:Number = 0; i < classes.length; i++) {
				var clazz:ClassInfo = classes[i];
				if (clazz.getType().valueOf() == concreteClass.valueOf()) {
					return clazz;
				}
			}
		}
		var subPackages:Array = getMemberPackagesByFlag(true);
		if (subPackages) {
			for (var i:Number = 0; i < subPackages.length; i++) {
				var clazz:ClassInfo = PackageInfo(subPackages[i]).getMemberClassByClass(concreteClass);
				if (clazz) return clazz;
			}
		}
		return null;
	}
	
	/**
	 * @overload #getMemberPackageByName
	 * @overload #getMemberPackageByPackage
	 */
	public function getMemberPackage(package):PackageInfo {
		var o:Overload = new Overload(this);
		o.addHandler([String], getMemberPackageByName);
		o.addHandler([Object], getMemberPackageByPackage);
		return o.forward(arguments);
	}
	
	/**
	 * Returns the package info corresponding to the passed-in {@code packageName}.
	 *
	 * <p>If the member package with the passed-in {@code packageName} cannot be found
	 * directly in the represented package its sub-packages are searched through.
	 * 
	 * <p>{@code null} will be returned if:
	 * <ul>
	 *   <li>The passed-in {@code packageName} is {@code null} or {@code undefined}.</li>
	 *   <li>The {@link #getMemberPackages} method returns {@code null}.</li>
	 *   <li>There is no package with the given {@code packageName}.</li>
	 * </ul>
	 *
	 * @param packageName the name of the package
	 * @return the package info corresponding to the passed-in {@code packageName}
	 */
	public function getMemberPackageByName(packageName:String):PackageInfo {
		if (packageName == null) return null;
		if (getMemberPackagesByFlag(true)) {
			if (members["packages"][packageName]) return members["packages"][packageName];
			var subPackages:Array = members["packages"];
			for (var i:Number = 0; i < subPackages.length; i++) {
				var package:PackageInfo = PackageInfo(subPackages[i]).getMemberPackageByName(packageName);
				if (package) return package;
			}
		}
		return null;
	}
	
	/**
	 * Returns the package info corresponding to the passed-in {@code concretePackage}.
	 *
	 * <p>If the member package corresponding to the passed-in {@code concretePackage}
	 * cannot be found directly in the represented package its sub-packages are
	 * searched through.
	 * 
	 * <p>{@code null} will be returned if:
	 * <ul>
	 *   <li>The passed-in {@code concretePackage} is {@code null} or {@code undefined}.</li>
	 *   <li>The {@link #getMemberPackages} method returns {@code null}.</li>
	 *   <li>A package matching the passed-in {@code concretePackage} could not be found.</li>
	 * </ul>
	 *
	 * @param concretePackage the concrete package the corresponding package info shall
	 * be returned for
	 * @return the package info corresponding to the passed-in {@code concretePackage}
	 */
	public function getMemberPackageByPackage(concretePackage):PackageInfo {
		if (concretePackage == null) return null;
		var packages:Array = getMemberPackagesByFlag(true);
		if (packages) {
			for (var i:Number = 0; i < packages.length; i++) {
				var package:PackageInfo = packages[i];
				if (package.getPackage().valueOf() == concretePackage.valueOf()) {
					return package;
				}
			}
			for (var i:Number = 0; i < packages.length; i++) {
				var package:PackageInfo = PackageInfo(packages[i]).getMemberPackageByPackage(concretePackage);
				if (package) return package;
			}
		}
		return null;
	}
	
	/**
	 * Returns whether this package is a root package.
	 *
	 * <p>It is supposed to be a root package when its parent is {@code null}.
	 *
	 * @return {@code true} if this package info represents a root package else {@code false}
	 */
	public function isRoot(Void):Boolean {
		return !getParent();
	}
	
	/** 
	 * Returns {@code true} if this package is the parent package of the passed-in
	 * {@code package}.
	 * 
	 * <p>{@code false} will be returned if:
	 * <ul>
	 *   <li>The passed-in {@code package} is not a parent package of this package.</li>
	 *   <li>The passed-in {@code package} is {@code null} or {@code undefined}.</li>
	 *   <li>The passed-in {@code package} equals this {@code package}.</li>
	 *   <li>The passed-in {@code package}'s {@code isRoot} method returns {@code true}.</li>
	 * </ul>
	 * 
	 * @param package package this package may be a parent of
	 * @return {@code true} if this package is the parent of the passed-in {@code package}
	 */
	public function isParentPackage(package:PackageInfo):Boolean {
		if (!package) return false;
		if (package == this) return false;
		while (package) {
			if (package.isRoot()) return false;
			package = package.getParent();
			if (package == this) return true;
		}
		return false;
	}
	
	/**
	 * Returns the string representation of this instance.
	 * 
	 * <p>The string representation is constructed as follows:
	 * <pre>
	 *   [reflection fullyQualifiedNameOfReflectedPackage]
	 * </pre>
	 * 
	 * @param displayContent (optional) a {@code Boolean} that determines whether to
	 * render this package's content recursively {@code true} or not {@code false}
	 * @return this instance's string representation
	 */
	public function toString():String {
		var result:String = "[reflection " + getFullName();
		if (arguments[0] == true) {
			var members:Array = getMembers();
			for (var i:Number = 0; i < members.length; i++) {
				result += "\n" + StringUtil.addSpaceIndent(members[i].toString(true), 2);
			}
			if (members.length > 0) {
				result += "\n";
			}
		}

		return (result + "]");
	}
	
}