using System;
using System.Collections;
using System.Collections.Specialized;

namespace FlashSocketServer.Log
{
	/// <summary>
	/// Represents a collection of FlashLogEntry objects. This class contains
	/// methods for common collection operations as well as methods to return
	/// filtered subsets of the collection.
	/// </summary>
	public class FlashLogEntryCollection : CollectionBase
	{
		private StringCollection m_classnames;
		private StringCollection m_namespaces;

		public FlashLogEntryCollection()
		{
			m_classnames = new StringCollection();
			m_namespaces = new StringCollection();
		}

		#region Public Methods

		/// <summary>
		/// Adds a log entry to the collection.
		/// </summary>
		/// <param name="logEntry"></param>
		public void Add(FlashLogEntry logEntry)
		{
			List.Add(logEntry);
		}


		/// <summary>
		/// Removes the log entry at index from the collection.
		/// </summary>
		/// <param name="index"></param>
		public void Remove(int index)
		{
			if (index < 0 || index > Count + 1)
			{
				throw new IndexOutOfRangeException(index + " is not a valid index");
			}

			List.Remove(index);
		}


		/// <summary>
		/// Gets the item at index. This is called by the array indexer.
		/// </summary>
		/// <param name="index"></param>
		/// <returns></returns>
		public FlashLogEntry Item(int index)
		{
			if (index < 0 || index > Count + 1)
			{
				throw new IndexOutOfRangeException(index + " is not a valid index");
			}

			return List[index] as FlashLogEntry;
			
		}


		/// <summary>
		/// Filters and returns a copy of the collection.
		/// </summary>
		/// <param name="filters"></param>
		/// <returns></returns>
		public FlashLogEntryCollection GetFilteredSet(LogFilter[] filters)
		{
			FlashLogEntryCollection ret = new FlashLogEntryCollection();
			
			//
			// Cycle through the entries to determine which
			// entries match the criteria imposed.
			//
			foreach (FlashLogEntry entry in this)
			{
				if (PassesFilters(entry, filters))
					ret.Add(entry);
			}

			return ret;
		}

		#endregion

		private bool PassesFilters(FlashLogEntry entry, LogFilter[] filters)
		{
			foreach (LogFilter f in filters)
			{
				if (f == null)
					continue;

				switch (f.Type)
				{
					case FilterType.Class:

						if (entry.ClassName != (string) f.Criteria)
							return false;

						break;

					case FilterType.Namespace:
	
						if (entry.Namespace != (string) f.Criteria)
							return false;

						break;

					case FilterType.LogLevel:
						
						if (entry.Level < (LogLevel) f.Criteria)
							return false;

						break;

				}
			}

			return true;
		}

		#region Internal Event Handlers, Events (and their delegates)

		public delegate void CriteriaAddedHandler(FlashLogEntryCollection entries, string newClass);
		public event CriteriaAddedHandler ClassAdded;
		public event CriteriaAddedHandler NamespaceAdded;

		public delegate void EntryAddedHandler(FlashLogEntryCollection entries, FlashLogEntry newEntry);
		public event EntryAddedHandler EntryAdded;

		protected override void OnInsert(int index, object value)
		{
			FlashLogEntry entry = value as FlashLogEntry;

			//
			// Dispatch entry added event.
			//
			if (EntryAdded != null)
				EntryAdded(this, entry);

			if (!m_classnames.Contains(entry.ClassName))
			{
				//
				// Add the class name to the array.
				//
				m_classnames.Add(entry.ClassName);

				//
				// Dispatch the event.
				//
				if (ClassAdded != null)
					ClassAdded(this, entry.ClassName);
			}

			if (!m_namespaces.Contains(entry.Namespace))
			{
				//
				// Add the class name to the array.
				//
				m_namespaces.Add(entry.Namespace);

				//
				// Dispatch the event.
				//
				if (NamespaceAdded != null)
					NamespaceAdded(this, entry.Namespace);
			}
			
			
		}
		
		#endregion

	}
}
