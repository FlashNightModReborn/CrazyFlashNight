using System;
using System.Xml;
using System.Collections;
using System.Windows.Forms;

namespace FlashSocketServer.Explore
{
	/// <summary>
	/// Represents an object that exists within the Flash environment.
	/// </summary>
	public class FlashObject
	{
		/// <summary>
		/// All possible "types" of Flash objects, as returned by the typeof() function
		/// in Flash.
		/// </summary>
		public enum ObjectType
		{
			String,
			MovieClip,
			Number,
			Boolean,
			Date,
			Object,
			Function,
			Null,
			Undefined
		}
	
		private static Hashtable g_typemappings;

		#region Member Variables

		/// <summary>
		/// This object's type as returned by the typeof() function in Flash.
		/// </summary>
		private ObjectType m_type;

		/// <summary>
		/// This object's path.
		/// </summary>
		private ObjectPath m_path;

		/// <summary>
		/// The value of this object.
		/// </summary>
		private string m_value;

		/// <summary>
		/// The properties of this object.
		/// </summary>
		private FlashObjectCollection m_properties;

		/// <summary>
		/// This object's parent object.
		/// </summary>
		private FlashObject m_parent;

		/// <summary>
		/// This object's tree node.
		/// </summary>
		private TreeNode m_treenode;

		#endregion

		#region Constructors

		/// <summary>
		/// Creates a new instance of FlashObject.
		/// </summary>
		private FlashObject()
		{
			m_properties = new FlashObjectCollection();
			m_parent = null;
			m_treenode = new TreeNode();
			m_treenode.Tag = this;
			m_treenode.Nodes.Add(new TreeNode("Loading..."));
		}


		/// <summary>
		/// Creates a new FlashObject with path.
		/// </summary>
		/// <param name="path"></param>
		public FlashObject(string path, ObjectType type)
			: this()
		{
			m_path = new ObjectPath(path);
			m_type = type;

			if (m_type == ObjectType.MovieClip || m_type == ObjectType.Object)
				m_treenode.Text = path;
			else
				m_treenode.Nodes.RemoveAt(0); // no need for a node
		}


		/// <summary>
		/// Creates a new instance of FlashObject.
		/// </summary>
		/// <param name="node">
		/// The client response data.
		/// </param>
		public FlashObject(XmlNode node) : this(
			node.Attributes["path"].Value,
			(ObjectType) g_typemappings[node.Attributes["objecttype"].Value])
		{
			//
			// Set the value
			//
			m_value = node.Attributes["value"].Value;
            
			//
			// Add the children.
			//
			FlashObject childobj;

			foreach (XmlNode child in node.ChildNodes)
			{
				//
				// Make sure it's a property node.
				//
				if (child.Name != "property")
					continue;

				childobj = new FlashObject(child, this);
				m_properties.Add(childobj);

				if (childobj.m_type == ObjectType.MovieClip || childobj.m_type == ObjectType.Object)
					m_treenode.Nodes.Add(childobj.m_treenode);
			}
		}


		/// <summary>
		/// Creates a new instance of FlashObject, fills it, and sets its parent.
		/// </summary>
		/// <param name="node">
		/// The client response data.
		/// </param>
		/// <param name="parent">
		/// The object's parent.
		/// </param>
		public FlashObject(XmlNode node, FlashObject parent)
			: this(node)
		{
			m_parent = parent;
		}


		/// <summary>
		/// Static constructor. Sets up the type mapping table.
		/// </summary>
		static FlashObject()
		{
			g_typemappings = new Hashtable();
			g_typemappings.Add("string", ObjectType.String);
			g_typemappings.Add("number", ObjectType.Number);
			g_typemappings.Add("boolean", ObjectType.Boolean);
			g_typemappings.Add("movieclip", ObjectType.MovieClip);
			g_typemappings.Add("date", ObjectType.Date);
			g_typemappings.Add("object", ObjectType.Object);
			g_typemappings.Add("function", ObjectType.Function);
			g_typemappings.Add("null", ObjectType.Null);
			g_typemappings.Add("undefined", ObjectType.Undefined);
		}

		#endregion

		#region Properties

		/// <summary>
		/// Gets the instance name of this object.
		/// </summary>
		public string InstanceName
		{
			get
			{
				return m_path.LastPart;
			}
		}


		/// <summary>
		/// Returns the value of this object.
		/// </summary>
		public string Value
		{
			get
			{
				return m_value;
			}
		}


		/// <summary>
		/// Gets the object's path as it existed in Flash.
		/// </summary>
		public ObjectPath Path
		{
			get
			{
				return m_path;
			}
		}

		/// <summary>
		/// True if the object has been filled with children.
		/// </summary>
		public bool IsFilled
		{
			get
			{
				return m_properties.Count > 0;
			}
		}

		/// <summary>
		/// Gets the object's type as returned by the typeof function in Flash.
		/// </summary>
		public ObjectType Type
		{
			get
			{
				return m_type;
			}
		}


		/// <summary>
		/// Gets the object's properties.
		/// </summary>
		public FlashObjectCollection Properties
		{
			get
			{
				return m_properties;
			}
		}


		public TreeNode TreeNode
		{
			get
			{
				if (m_type != ObjectType.MovieClip && m_type != ObjectType.Object)
				{
					throw new InvalidOperationException("A FlashObject of type " +
						m_type.ToString() + " cannot become a TreeNode");
				}

				return m_treenode;
			}
		}

		public string FullPath
		{
			get
			{
				return m_path.ToString();
			}
		}

		#endregion

		#region Public Methods

		public void Update(object newVer)
		{
			Update(newVer as FlashObject);
		}


		/// <summary>
		/// Updates the FlashObject with a newer version of itself.
		/// </summary>
		/// <param name="newVer"></param>
		public void Update(FlashObject newVer)
		{
			//
			// If not yet filled, remove the Loading... node.
			//
			if (!IsFilled && m_treenode.Nodes.Count > 0)
			{
				m_treenode.Nodes.RemoveAt(0);
			}

			//
			// Update the value.
			//
			this.m_value = newVer.m_value;

			if (this.m_parent == null && newVer.m_parent != null)
			{
				this.m_parent = newVer.m_parent;
				this.m_parent.m_treenode.Nodes.Add(this.m_treenode);
			}

			IDictionaryEnumerator itr;

			//
			// Remove the properties that don't exist in the new one.
			//
			itr = m_properties.GetEnumerator();
			ArrayList toRemove = new ArrayList();

			while (itr.MoveNext()) // Find 'em
			{
				if (!newVer.m_properties.Contains(itr.Key as ObjectPath))
				{
					toRemove.Add(itr.Key);
				}
			}

			foreach (object key in toRemove) // Remove 'em
			{
				try
				{
					m_properties.Remove(key as ObjectPath);
				}
				catch
				{
				}
			}

			//
			// Update the properties
			//
			itr = newVer.m_properties.GetEnumerator();
			FlashObject current;

			while (itr.MoveNext())
			{
				current = itr.Value as FlashObject;
							
				//
				// If the object already exists, update it.
				//
				if (m_properties.Contains(current.Path))
				{
					((FlashObject) m_properties[current.Path]).Update(current);
					continue;
				}

				//
				// If the object doesn't exist, then add it.
				//

				//
				// Set parent (as it was previously referencing the update object)
				//
				current.m_parent = this;

				m_properties.Add(current);

				if (current.m_type != ObjectType.MovieClip && current.m_type != ObjectType.Object)
					continue;

				m_treenode.Nodes.Add(current.m_treenode);
			}
		}

		#endregion
	}
}
