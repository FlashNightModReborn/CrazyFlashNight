using System;

namespace FlashSocketServer.Log
{
	/// <summary>
	/// A single Flash log entry.
	/// </summary>
	public class FlashLogEntry
	{
		public LogLevel	Level;
		public string	FileName;
		public string	FullClassName;
		public string	MethodName;
		public int		LineNumber;
		public string	Message;
		public DateTime	TimeStamp;

		private string m_classname = "";
		private string m_namespace = "";

		public FlashLogEntry()
		{
		}


		public FlashLogEntry(
			LogLevel level, 
			string fileName,
			string className,
			string methodName,
			int lineNumber,
			string message,
			DateTime timeStamp)
		{
			Level = level;
			FileName = fileName;
			FullClassName = className;
			MethodName = methodName;
			LineNumber = lineNumber;
			Message = message;
			TimeStamp = timeStamp;
		}

		
		public FlashLogEntry(System.Xml.XmlNode node) : this(
			(LogLevel) int.Parse(node.Attributes["level"].Value),
			node.Attributes["file"].Value,
			node.Attributes["cls"].Value,
			node.Attributes["method"].Value,
			int.Parse(node.Attributes["line"].Value),
			node.Attributes["message"].Value,
			DateTime.Now)
		{
		}


		public string ClassName
		{
			get
			{
				if (m_classname.Length == 0)
					m_classname = FullClassName.Substring(FullClassName.LastIndexOf(".") + 1);

				return m_classname;
			}
		}

		public string Namespace
		{
			get
			{
				if (m_namespace.Length == 0)
					m_namespace = FullClassName.Substring(0, FullClassName.LastIndexOf("."));

				return m_namespace;
			}
		}
	}
}
