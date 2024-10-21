using System;
using System.Collections.Specialized;

namespace FlashSocketServer.Explore
{
	/// <summary>
	/// Represents an object's path.
	/// </summary>
	public class ObjectPath 
	{
		/// <summary>
		/// The seperator between path parts when represented as a string.
		/// </summary>
		private const char PATH_SEPERATOR = '.';

		/// <summary>
		/// The parts of the path.
		/// </summary>
		private StringCollection m_parts;


		#region Constructors

		/// <summary>
		/// Creates a new instance of ObjectPath.
		/// </summary>
		public ObjectPath()
		{
			m_parts = new StringCollection();
		}


		/// <summary>
		/// Creates a new instance of ObjectPath with the specified path.
		/// </summary>
		/// <param name="path">The path seperated by PATH_SEPERATOR characters.</param>
		public ObjectPath(string path) : this()
		{
			Parse(path);
		}
				
		#endregion

		#region Properties

		public string LastPart
		{
			get
			{
				return m_parts[m_parts.Count - 1];
			}
		}

		#endregion

		#region Public Methods

		/// <summary>
		/// Returns the object path as sliced from the specified index.
		/// </summary>
		/// <example>
		/// 
		/// </example>
		/// <param name="index"></param>
		/// <returns></returns>
		public ObjectPath SliceFrom(int index)
		{
			string slicedpath = "";

			for (int i = index; i < m_parts.Count - 1; i++)
				slicedpath += m_parts[i] + PATH_SEPERATOR.ToString();

			slicedpath += m_parts[m_parts.Count - 1];

			return new ObjectPath(slicedpath);
		}


		/// <summary>
		/// Returns the string representation of the path.
		/// 
		/// ie. path1.path2.objectName
		/// </summary>
		/// <returns>The path as a string</returns>
		public new string ToString()
		{
			string ret = "";

			for (int i = 0; i < m_parts.Count - 1; i++)
				ret += m_parts[i] + PATH_SEPERATOR.ToString();

			ret += m_parts[m_parts.Count - 1];

			return ret;
		}


		/// <summary>
		/// Gets the hash code for this ObjectPath object.
		/// </summary>
		/// <returns></returns>
		public override int GetHashCode() 
		{
			return ToString().GetHashCode();
		}


		/// <summary>
		/// Compares this object path with another object, and returns true
		/// if they are the same. Equality is not based on reference, but instead
		/// value.
		/// </summary>
		/// <param name="that"></param>
		/// <returns></returns>
		public override bool Equals(object that)
		{
			return that.GetHashCode() == this.GetHashCode();
		}

		#endregion

		#region Private Methods

		/// <summary>
		/// Parses a string into the path.
		/// </summary>
		/// <param name="path"></param>
		private void Parse(string path)
		{
			string[] parts = path.Split(PATH_SEPERATOR);

			foreach (string part in parts)
				m_parts.Add(part);
		}

		#endregion

		#region Indexers

		public string this[int index]
		{
			get
			{
				return m_parts[index];
			}
		}
					  
		#endregion
	}
}
