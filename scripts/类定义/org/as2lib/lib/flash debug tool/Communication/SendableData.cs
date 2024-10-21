using System;
using System.Xml;

namespace FlashSocketServer.Communication
{
	/// <summary>
	/// Represents data that can be sent to the Flash client.
	/// 
	/// To be subclassed for specific data.
	/// </summary>
	public abstract class SendableData
	{
		/// <summary>
		/// The default name for the underlying data node.
		/// </summary>
		protected const string NODE_NAME		= "request";

		/// <summary>
		/// The key into the node's attributes for request type.
		/// </summary>
		protected const string ATTKEY_TYPE		= "type";

		/// <summary>
		/// The node generating XmlDcoument.
		/// 
		/// Used because XmlNodes can not be directly instantiated.
		/// </summary>
		private static XmlDocument g_nodegenerator;

		/// <summary>
		/// The underlying data.
		/// </summary>
		protected XmlNode m_data;

		#region Constructors

		/// <summary>
		/// Creates a new instance of sendable data.
		/// 
		/// To be called by subclasses.
		/// </summary>
		/// <param name="type">
		/// The "type" attribute of the data.
		/// </param>
		public SendableData(string type)
			: this(NODE_NAME, type)
		{
		}


		/// <summary>
		/// Creates a new instance of sendable data using
		/// the specified string for the name of the underlying
		/// data node.
		/// </summary>
		/// <param name="nodeName">The name of the data node.</param>
		/// <param name="type">
		/// The "type" attribute of the data.
		/// </param>
		public SendableData(string nodeName, string type)
		{
			m_data = g_nodegenerator.CreateElement(nodeName);
			
			AddAttribute(ATTKEY_TYPE, type);
		}


		/// <summary>
		/// Static constructor.
		/// 
		/// Creates an XML Document to be used as a node generator.
		/// This must be done because XmlNodes can be directly instantiated.
		/// </summary>
		static SendableData()
		{
			g_nodegenerator = new XmlDocument();
		}

		#endregion

		#region Properties

		/// <summary>
		/// The data this contains.
		/// </summary>
		public XmlNode Data
		{
			get
			{
				return m_data;
			}
		}


		/// <summary>
		/// Returns the Xml representation of this object.
		/// </summary>
		public string Xml
		{
			get
			{
				return m_data.OuterXml;
			}
		}

		#endregion

		#region Public Methods


		/// <summary>
		/// Returns a string representation of the object.
		/// 
		/// This is the data to be sent to the server.
		/// </summary>
		/// <returns></returns>
		public new string ToString()
		{
			return m_data.ToString();
		}

		#endregion

		#region Protected Methods

		/// <summary>
		/// Adds an attribute to the underlying data node.
		/// </summary>
		/// <param name="name">The name of the attribute.</param>
		/// <param name="value">The value of the attribute.</param>
		protected void AddAttribute(string name, string value)
		{
			XmlAttribute att = g_nodegenerator.CreateAttribute(name);
			att.Value = value;
			m_data.Attributes.Append(att);
		}

		#endregion
	}
}
