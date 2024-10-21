using System;

namespace FlashSocketServer.Log
{
	public enum FilterType
	{
		LogLevel,
		Class,
		Namespace
	}

	/// <summary>
	/// Describes a filter to be applied to a FlashLogEntryCollection.
	/// </summary>
	public class LogFilter
	{
		private FilterType m_type;
		private object m_crit;

		public LogFilter(FilterType type, object value)
		{
			m_type = type;
			m_crit = value;
		}

		public FilterType Type
		{
			get
			{
				return m_type;
			}
		}

		public object Criteria
		{
			get
			{
				return m_crit;
			}
		}
				
	}
}
