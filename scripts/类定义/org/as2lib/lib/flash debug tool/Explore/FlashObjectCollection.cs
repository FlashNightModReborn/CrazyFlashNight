using System;
using System.Collections;

namespace FlashSocketServer.Explore
{
	/// <summary>
	/// Represents a collection of FlashObjects implemented as a dictionary,
	/// hashed on the object's path.
	/// </summary>
	public class FlashObjectCollection : DictionaryBase
	{
		public FlashObjectCollection()
		{
		}

		public void Add(FlashObject obj)
		{
			Dictionary.Add(obj.Path, obj);
		}

		public void Remove(ObjectPath path)
		{
			Dictionary.Remove(path);
		}

		public bool Contains(ObjectPath path)
		{
			return Dictionary.Contains(path);
		}

		public FlashObject this[string path]
		{
			get
			{
				return this[new ObjectPath(path)];
			}
			set
			{
				this[new ObjectPath(path)] = value;
			}
		}

		public FlashObject this[ObjectPath path]
		{
			get
			{
				return Dictionary[path] as FlashObject;
			}
			set
			{
				Dictionary[path] = value;
			}
		}
	}
}
