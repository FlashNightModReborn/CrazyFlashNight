using System;
using System.Xml;
using System.Xml.Serialization;
using System.IO;
using System.Windows.Forms;

namespace FlashSocketServer
{
	/// <summary>
	/// Holds user preferences information.
	/// </summary>
	public class UserPreferences
	{
		/// <summary>
		/// The name of the preferences file.
		/// </summary>
		private const string FILENAME = "userprefs.xml";

		/// <summary>
		/// The singleton.
		/// </summary>
		private static UserPreferences g_current;

		/// <summary>
		/// The port.
		/// </summary>
		private int m_port;

		/// <summary>
		/// The window size.
		/// </summary>
		private System.Drawing.Rectangle m_windowsize;

		/// <summary>
		/// The preferred log level.
		/// </summary>
		private Log.LogLevel m_level;

		/// <summary>
		/// Constructs a new instance of UserPreferences.
		/// </summary>
		public UserPreferences()
		{	
		}

		#region Properties

		/// <summary>
		/// Gets or sets the port.
		/// </summary>
		public int Port
		{
			get
			{
				return m_port;
			}
			set
			{
				m_port = value;
			}
		}


		/// <summary>
		/// The preferred window size.
		/// </summary>
		public System.Drawing.Rectangle WindowSize
		{
			get
			{
				return m_windowsize;
			}
			set
			{
				m_windowsize = value;
			}
		}
		
		#endregion

		#region Static Properties

			/// <summary>
			/// Gets the current user's properties.
			/// </summary>
			public static UserPreferences Current
		{
			get
			{
				return g_current;
			}
		}


		/// <summary>
		/// Gets the location of the user preferences file.
		/// </summary>
		private static string FilePath
		{
			get
			{
				//
				// Build path
				//
				string filePath;

				filePath = Path.Combine(
					Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
					Application.CompanyName);
				filePath = Path.Combine(
					filePath,
					Application.ProductName);
				filePath = Path.Combine(
					filePath,
					FILENAME);
				
				return filePath;
			}
		}

		#endregion

		static UserPreferences()
		{
			g_current = new UserPreferences();
		}

		/// <summary>
		/// Saves the current user preferences to a file.
		/// </summary>
		public static void Save()
		{
			try
			{
				//
				// Write the file.
				//
				TextWriter settingsFile = new StreamWriter(FilePath);
				XmlSerializer xmls = new XmlSerializer(g_current.GetType());
				xmls.Serialize(settingsFile, g_current);
				settingsFile.Close();
			}
			catch (Exception e)
			{
				throw e;
			}
		}

		/// <summary>
		/// Loads the current user preferences from a file.
		/// </summary>
		public static void Load()
		{
			//
			// Create directory if needed.
			//
			Directory.CreateDirectory(Path.GetDirectoryName(FilePath));
			
			if (!File.Exists(FilePath))
				return;

			try
			{
				TextReader settingsFile = new StreamReader(FilePath);
				XmlSerializer xmls = new XmlSerializer(g_current.GetType());
				g_current = xmls.Deserialize(settingsFile) as UserPreferences;
				settingsFile.Close();
			}
			catch (Exception e)
			{
				throw e;
			}
		}
	}
}
