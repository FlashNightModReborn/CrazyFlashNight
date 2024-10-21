using System;
using System.Xml;
using System.Collections;

using FlashSocketServer.Communication;


namespace FlashSocketServer.Explore
{
	/// <summary>
	/// Manages objects, object property requests, and the internal object tree.
	/// </summary>
	public class ObjectManager
	{
		private FlashSocket m_socket;
		private System.Windows.Forms.Control m_threadcontrol;
		private Hashtable m_requests;
		private FlashObjectCollection m_flatcache;
		private FlashObject m_rootnode;
		private FlashObject m_globalnode;

		/// <summary>
		/// Creates a new instance of ObjectManager.
		/// </summary>
		/// <param name="socket">The socket used to communicate with Flash.</param>
		public ObjectManager(FlashSocket socket, System.Windows.Forms.Control controlForThread)
		{
			m_requests = new Hashtable();
			m_flatcache = new FlashObjectCollection();

			m_rootnode = new FlashObject("_root", FlashObject.ObjectType.MovieClip);
			m_globalnode = new FlashObject("_global", FlashObject.ObjectType.Object);

			m_flatcache.Add(m_rootnode);
			m_flatcache.Add(m_globalnode);

			m_threadcontrol = controlForThread;

			m_socket = socket;
			m_socket.DataRecieved += new FlashSocket.DataRecievedHandler(socket_DataRecieved);
		}

		#region Properties

		public FlashObject Root
		{
			get
			{
				return m_rootnode;
			}
		}


		public FlashObject Global
		{
			get
			{
				return m_globalnode;
			}
		}

		#endregion

		#region Public Methods

		/// <summary>
		/// Requests an object's properties.
		/// </summary>
		/// <param name="objectPath"></param>
		public void RequestObjectProperties(ObjectPath objectPath, ObjectRecievedHandler handler)
		{
			RequestObjectProperties(objectPath.ToString(), handler);
		}


		/// <summary>
		/// Requests an object's properties.
		/// </summary>
		/// <param name="objectPath"></param>
		public void RequestObjectProperties(string objectPath, ObjectRecievedHandler handler)
		{
			if (!m_requests.ContainsKey(objectPath))
			{
				//
				// If this request has not yet been made, prepare the request bucket.
				//
				m_requests.Add(objectPath, new ArrayList());
				((ArrayList) m_requests[objectPath]).Add(handler);	
			}
			else
			{
				//
				// If this request has already been made, just add another callback
				// and return.
				//
				((ArrayList) m_requests[objectPath]).Add(handler);
				return;
			}

			ObjectPropertyRequest request = new ObjectPropertyRequest(objectPath);
			m_socket.Send(request);
		}

		#endregion

		#region Events

		/// <summary>
		/// Represents the delegate that will handle a FlashObject after it has been recieved.
		/// </summary>
		public delegate void ObjectRecievedHandler(FlashObject obj);

		/// <summary>
		/// Fired when a Flash object's properties have been recieved.
		/// </summary>
		public event ObjectRecievedHandler ObjectRecieved;

		/// <summary>
		/// Parses the recieved data from the socket.
		/// </summary>
		/// <param name="socket"></param>
		/// <param name="node"></param>
		private void socket_DataRecieved(System.Net.Sockets.Socket socket, XmlNode node)
		{
			if (node.Attributes["type"].Value != "objectproperties")
				return;

			FlashObject obj = new FlashObject(node);
			
			//
			// Add object to cache, hashing on the entire path.
			//
			if (m_flatcache.Contains(obj.Path))
			{
				FlashObject updateObj = obj;

				//
				// Set obj as the object already in the cache.
				//
				obj = m_flatcache[obj.Path] as FlashObject;
				
				try
				{
					m_threadcontrol.Invoke(new ObjectEventHandler(
						obj.Update), new object[1] {updateObj});
				}
				catch (Exception e)
				{
					System.Diagnostics.Debugger.Log(0, "1", e.ToString());
				}
			}
			else
			{
				m_flatcache.Add(obj);
			}

			//
			// Add all the property objects to the cache.
			//
			IDictionaryEnumerator itr = obj.Properties.GetEnumerator();
			FlashObject prop;

			while (itr.MoveNext())
			{
				prop = itr.Value as FlashObject;

				//
				// Add the object if it doesn't exist.
				//
				if (!m_flatcache.Contains(prop.Path))
				{
					m_flatcache.Add(prop);
				}
			}

			//
			// Inform object specific handlers.
			//
			ArrayList handlers = m_requests[obj.Path.ToString()] as ArrayList;

			foreach (ObjectRecievedHandler hndlr in handlers)
				hndlr(obj);

			//
			// Remove the handler array.
			//
			m_requests.Remove(obj.Path.ToString());

			//
			// Dispatch ObjectRecieved event.
			//
			if (ObjectRecieved != null)
				ObjectRecieved(obj);
		}

		#endregion
	}
}
