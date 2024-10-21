using System;
using System.Net;
using System.Net.Sockets;
using System.Collections.Specialized;
using System.Xml;

namespace FlashSocketServer.Log
{
	/// <summary>
	/// Log levels associated with Flash log traces.
	/// </summary>
	public enum LogLevel
	{
		All		= 1,
		Debug	= 2,
		Info	= 3,
		Warning	= 4,
		Error	= 5,
		Fatal	= 6,
		None	= 7
	}

	/// <summary>
	/// Parses Flash logging messages as recieved through an XMLSocket connection
	/// into collections of FlashLogEntry objects which can be filtered on a variety
	/// of criteria.
	/// </summary>
	public class FlashLogger
	{
		#region Class Variables

		private static char[] g_splitchars;

		#endregion

		#region Member Variables

		private FlashLogEntryCollection m_entries;

		#endregion


		/// <summary>
		/// Creates a new instance of FlashLogger.
		/// </summary>
		public FlashLogger()
		{
			m_entries = new FlashLogEntryCollection();
		}


		#region Properties

		/// <summary>
		/// Gets the log entries.
		/// </summary>
		public FlashLogEntryCollection LogEntries
		{
			get
			{
				return m_entries;
			}
		}

		#endregion

		#region Event Handlers

		/// <summary>
		/// Parses out the string data into a FlashLogEntry and adds it to
		/// the LogEntries collection.
		/// </summary>
		/// <param name="socket"></param>
		/// <param name="data"></param>
		public void FlashSocket_DataRecieved(Socket socket, XmlNode node)
		{
			//
			// Check that the node is for us.
			//
			if (node.Attributes["type"] == null)
				return;

			if (node.Attributes["type"].Value != "trace")
				return;

			//
			// Create and fill the new log entry.
			//
			FlashLogEntry logEntry = new FlashLogEntry(node);

			//
			// Add the entry to the collection.
			//
			m_entries.Add(logEntry);
		}

		#endregion

		#region Private Methods

		/// <summary>
		/// Removes blank elements from the string array
		/// </summary>
		/// <param name="src"></param>
		/// <returns></returns>
		private string[] RemoveBlankElements(string[] src)
		{
			StringCollection strings = new StringCollection();

			foreach (string s in src)
			{
				if (s.Length == 0)
					continue;

				strings.Add(s);
			}

			string[] ret = new string[strings.Count];
			strings.CopyTo(ret, 0);

			return ret;
		}

		#endregion

		static FlashLogger()
		{
			g_splitchars = new char[] {'~'};
		}
	}
}
