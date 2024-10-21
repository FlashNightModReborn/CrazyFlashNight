using System;
using FlashSocketServer.Communication;

namespace FlashSocketServer.Explore
{
	/// <summary>
	/// Summary description for ObjectPropertyRequest.
	/// </summary>
	public class ObjectPropertyRequest : SendableData
	{
		private const string REQUEST_TYPE	= "objectproperties";
		private const string ATTKEY_PATH	= "path";

		#region Construtors

		/// <summary>
		/// Creates a new instance of ObjectPropertyRequest for the
		/// object at the specified path.
		/// </summary>
		/// <param name="path">
		/// A string, with the path seperated by "." characters.
		/// </param>
		public ObjectPropertyRequest(string path) 
			: base(REQUEST_TYPE)
		{
			AddAttribute(ATTKEY_PATH, path);
		}


		/// <summary>
		/// Creates a new instance of ObjectPropertyRequest for the
		/// object at the specified path.
		/// </summary>
		/// <param name="path">The ObjectPath of the object.</param>
		public ObjectPropertyRequest(ObjectPath path)
			: this(path.ToString())
		{
		}

		#endregion

		#region Properties

		#endregion
	}
}
