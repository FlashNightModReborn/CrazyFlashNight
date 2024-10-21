using System;
using System.Drawing;
using System.Collections;
using System.ComponentModel;
using System.Windows.Forms;
using System.Data;
using System.Net;
using System.Net.Sockets;
using FlashSocketServer.Log;
using SourceGrid2.Cells.Real;

using FlashSocketServer.Communication;

namespace FlashSocketServer
{
	/// <summary>
	/// Summary description for Form1.
	/// </summary>
	public class LoggerForm : System.Windows.Forms.UserControl
	{
		private FlashLogger m_logger;
		private int m_grid_delta_x;
		private int m_grid_delta_y;
		private FlashLogEntry m_selectedentry;
		private FlashLogEntryCollection m_entries;

		#region Controls

		#endregion

		private SourceGrid2.Grid gridLog;
		private System.Windows.Forms.ComboBox cbNamespaces;
		private System.Windows.Forms.ComboBox cbClasses;
		private System.Windows.Forms.Button btnClear;
		private System.Windows.Forms.Button btnProperties;
		private EntryPropertiesForm frmProperties;
		private System.Windows.Forms.ComboBox cbLogLevel;

		/// <summary>
		/// Required designer variable.
		/// </summary>
		private System.ComponentModel.Container components = null;

		public LoggerForm(FlashSocket socket)
		{
			InitializeComponent();

			//
			// Component initialization.
			//

			cbClasses.SelectedIndex = 0;
			cbNamespaces.SelectedIndex = 0;
			cbLogLevel.SelectedIndex = 0;

			//
			// Create necessary variables
			//
			m_logger = new FlashLogger();
			m_entries = new FlashLogEntryCollection();
			
			//
			// Create child windows
			//
			frmProperties = new EntryPropertiesForm();

			//
			// Set up delegation
			//
			socket.DataRecieved += 
				new FlashSocket.DataRecievedHandler(m_logger.FlashSocket_DataRecieved);
			m_logger.LogEntries.ClassAdded += new FlashLogEntryCollection.CriteriaAddedHandler(
				Log_ClassAdded);
			m_logger.LogEntries.NamespaceAdded += new FlashLogEntryCollection.CriteriaAddedHandler(
				Log_NamespaceAdded);
			m_logger.LogEntries.EntryAdded += new FlashLogEntryCollection.EntryAddedHandler(
				Log_EntryAdded);

			//
			// Set up the grid
			//
			SetupGrid();
			gridLog.Selection.FocusRowEntered +=
				new SourceGrid2.RowEventHandler(gridLog_FocusRowEntered);

			//
			// Layout variables
			//
			m_grid_delta_x = this.Width - gridLog.Width;
			m_grid_delta_y = this.Height - gridLog.Height;

			
			
		}

		#region Destructor

		/// <summary>
		/// Clean up any resources being used.
		/// </summary>
		protected override void Dispose( bool disposing )
		{
			if( disposing )
			{
				if (components != null) 
				{
					components.Dispose();
				}
			}
			base.Dispose( disposing );
		}

		#endregion
		
		#region Windows Form Designer generated code
		/// <summary>
		/// Required method for Designer support - do not modify
		/// the contents of this method with the code editor.
		/// </summary>
		private void InitializeComponent()
		{
			System.Resources.ResourceManager resources = new System.Resources.ResourceManager(typeof(LoggerForm));
			this.cbClasses = new System.Windows.Forms.ComboBox();
			this.cbNamespaces = new System.Windows.Forms.ComboBox();
			this.gridLog = new SourceGrid2.Grid();
			this.btnClear = new System.Windows.Forms.Button();
			this.btnProperties = new System.Windows.Forms.Button();
			this.cbLogLevel = new System.Windows.Forms.ComboBox();
			this.SuspendLayout();
			// 
			// cbClasses
			// 
			this.cbClasses.DropDownStyle = System.Windows.Forms.ComboBoxStyle.DropDownList;
			this.cbClasses.Items.AddRange(new object[] {
														   "All"});
			this.cbClasses.Location = new System.Drawing.Point(504, 8);
			this.cbClasses.Name = "cbClasses";
			this.cbClasses.Size = new System.Drawing.Size(120, 21);
			this.cbClasses.TabIndex = 9;
			this.cbClasses.SelectedIndexChanged += new System.EventHandler(this.cbClasses_SelectedIndexChanged);
			// 
			// cbNamespaces
			// 
			this.cbNamespaces.DropDownStyle = System.Windows.Forms.ComboBoxStyle.DropDownList;
			this.cbNamespaces.Items.AddRange(new object[] {
															  "All"});
			this.cbNamespaces.Location = new System.Drawing.Point(328, 8);
			this.cbNamespaces.Name = "cbNamespaces";
			this.cbNamespaces.Size = new System.Drawing.Size(168, 21);
			this.cbNamespaces.TabIndex = 7;
			this.cbNamespaces.SelectedIndexChanged += new System.EventHandler(this.cbNamespaces_SelectedIndexChanged);
			// 
			// gridLog
			// 
			this.gridLog.AutoSizeMinHeight = 10;
			this.gridLog.AutoSizeMinWidth = 10;
			this.gridLog.AutoStretchColumnsToFitWidth = false;
			this.gridLog.AutoStretchRowsToFitHeight = false;
			this.gridLog.BackColor = System.Drawing.SystemColors.ControlLightLight;
			this.gridLog.ContextMenuStyle = SourceGrid2.ContextMenuStyle.None;
			this.gridLog.CustomSort = false;
			this.gridLog.GridToolTipActive = true;
			this.gridLog.Location = new System.Drawing.Point(8, 40);
			this.gridLog.Name = "gridLog";
			this.gridLog.Size = new System.Drawing.Size(616, 224);
			this.gridLog.SpecialKeys = SourceGrid2.GridSpecialKeys.Default;
			this.gridLog.TabIndex = 6;
			// 
			// btnClear
			// 
			this.btnClear.Location = new System.Drawing.Point(8, 8);
			this.btnClear.Name = "btnClear";
			this.btnClear.TabIndex = 10;
			this.btnClear.Text = "&Clear";
			this.btnClear.Click += new System.EventHandler(this.btnClear_Click);
			// 
			// btnProperties
			// 
			this.btnProperties.Enabled = false;
			this.btnProperties.Location = new System.Drawing.Point(8, 272);
			this.btnProperties.Name = "btnProperties";
			this.btnProperties.TabIndex = 11;
			this.btnProperties.Text = "Properties";
			this.btnProperties.Click += new System.EventHandler(this.btnProperties_Click);
			// 
			// cbLogLevel
			// 
			this.cbLogLevel.DropDownStyle = System.Windows.Forms.ComboBoxStyle.DropDownList;
			this.cbLogLevel.Items.AddRange(new object[] {
															"All",
															"Debug",
															"Info",
															"Warning",
															"Error",
															"Fatal",
															"None"});
			this.cbLogLevel.Location = new System.Drawing.Point(208, 8);
			this.cbLogLevel.Name = "cbLogLevel";
			this.cbLogLevel.Size = new System.Drawing.Size(112, 21);
			this.cbLogLevel.TabIndex = 12;
			this.cbLogLevel.SelectedIndexChanged += new System.EventHandler(this.cbLogLevel_SelectedIndexChanged);
			// 
			// LoggerForm
			// 

			this.ClientSize = new System.Drawing.Size(632, 301);
			this.Controls.AddRange(new System.Windows.Forms.Control[] {
																		  this.cbLogLevel,
																		  this.btnProperties,
																		  this.btnClear,
																		  this.gridLog,
																		  this.cbClasses,
																		  this.cbNamespaces});
			this.Name = "LoggerForm";
			this.Text = "Flash Logger";
			this.Layout += new System.Windows.Forms.LayoutEventHandler(this.ServerForm_Layout);
			this.ResumeLayout(false);

		}
		#endregion

		#region Properties

		public FlashLogger Logger
		{
			get
			{
				return m_logger;
			}
		}

		#endregion

		#region Public Methods

		public new void PerformLayout()
		{
			//gridLog.Width = this.Width - 24;
			gridLog.Width = this.Width - m_grid_delta_x;
			gridLog.Height = this.Height - m_grid_delta_y;
			btnProperties.Location = new Point(btnProperties.Location.X, gridLog.Bottom + 8);
			
			cbNamespaces.Location = new Point(this.Width - cbNamespaces.Width - 16, cbNamespaces.Location.Y);
			cbClasses.Location = new Point(cbNamespaces.Left - 8 - cbClasses.Width, cbClasses.Location.Y);
			cbLogLevel.Location = new Point(cbClasses.Left - 8 - cbLogLevel.Width, cbLogLevel.Location.Y);
		}

		public void ClearGridContents()
		{
			if (gridLog.Rows.Count > 1)
				gridLog.Rows.RemoveRange(1, gridLog.Rows.Count - 1);

			btnProperties.Enabled = false;
		}

		#endregion

		#region Private Methods

		private void SetupGrid()
		{
			gridLog.Selection.SelectionMode = SourceGrid2.GridSelectionMode.Row;
			gridLog.BorderStyle = BorderStyle.FixedSingle;
			gridLog.ColumnsCount = 8;
			gridLog.FixedRows = 1;

			//
			// Create column headers
			//
			SourceGrid2.Cells.Real.ColumnHeader header;

			gridLog.Rows.Insert(0);
			gridLog[0,0] = new SourceGrid2.Cells.Real.ColumnHeader("Level");
			gridLog[0,1] = new SourceGrid2.Cells.Real.ColumnHeader("Namespace");
			gridLog[0,2] = new SourceGrid2.Cells.Real.ColumnHeader("Class");
			gridLog[0,3] = new SourceGrid2.Cells.Real.ColumnHeader("Method");
			gridLog[0,4] = new SourceGrid2.Cells.Real.ColumnHeader("Line");
			gridLog[0,5] = new SourceGrid2.Cells.Real.ColumnHeader("Message");
			gridLog[0,6] = new SourceGrid2.Cells.Real.ColumnHeader("File");

			header = new SourceGrid2.Cells.Real.ColumnHeader("Date");
			gridLog[0,7] = header;

			gridLog.Columns[0].Width = 60;
			gridLog.Columns[1].Width = 120;
			gridLog.Columns[2].Width = 120;
			gridLog.Columns[3].Width = 120;
			gridLog.Columns[5].Width = 200;
			gridLog.Columns[6].Width = 150;
			gridLog.Columns[7].Width = 150;
			
		}

		private void AddLogEntryToGrid(object entry)
		{
			AddLogEntryToGrid(entry as FlashLogEntry);
		}

		private void AddLogEntryToGrid(FlashLogEntry entry)
		{
			//! validate against filters

			gridLog.Rows.Insert(1);

			//
			// Create cells
			//
			SourceGrid2.Cells.Real.Cell cell;
			
			//
			// Level
			//
			cell = new SourceGrid2.Cells.Real.Cell(entry.Level.ToString());
			gridLog[1,0] = cell;
			cell.BackColor = GetLevelCellColour(entry.Level);
 
			//
			// Namespace
			//
			cell = new SourceGrid2.Cells.Real.Cell(entry.Namespace);
			gridLog[1,1] = cell;

			//
			// Class name
			//
			cell = new SourceGrid2.Cells.Real.Cell(entry.ClassName);
			gridLog[1,2] = cell;

			//
			// Method name
			//
			cell = new SourceGrid2.Cells.Real.Cell(entry.MethodName);
			gridLog[1,3] = cell;

			//
			// Line number
			//
			cell = new SourceGrid2.Cells.Real.Cell(entry.LineNumber);
			gridLog[1,4] = cell;

			//
			// Message
			//
			cell = new SourceGrid2.Cells.Real.Cell(entry.Message);
			cell.WordWrap = true;
			gridLog[1,5] = cell;

			//
			// File name
			//
			cell = new SourceGrid2.Cells.Real.Cell(entry.FileName);
			gridLog[1,6] = cell;

			//
			// Timestamp
			//
			cell = new SourceGrid2.Cells.Real.Cell(entry.TimeStamp.ToString("MM/dd/yyyy HH:mm:ss:ff"));
			gridLog[1,7] = cell;

			gridLog.Rows[1].AutoSize(true, 5, 5);

			//
			// Hold the associated entry.
			// 
			gridLog.Rows[1].Tag = entry;
		}

		private Color GetLevelCellColour(LogLevel level)
		{
			System.Drawing.Color c;

			switch (level)
			{
				case LogLevel.Debug:
					c = System.Drawing.Color.PowderBlue;
					break;

				case LogLevel.Info:
					c = System.Drawing.Color.White;
					break;

				case LogLevel.Warning:
					c = System.Drawing.Color.Orange;
					break;

				case LogLevel.Error:
					c = System.Drawing.Color.OrangeRed;
					break;

				case LogLevel.Fatal:
					c = System.Drawing.Color.Red;
					break;

				default:
					c = System.Drawing.Color.White;
					break;

			}

			return c;
		}

		private void ApplyFiltersAndDisplay()
		{
			//
			// Form construction not yet complete
			//
			if (m_entries == null)
				return;

			LogFilter[] filters = new LogFilter[3];
			int index = 0;

			if (cbClasses.SelectedIndex != 0)
				filters[index++] = new LogFilter(FilterType.Class, cbClasses.SelectedItem.ToString());

			if (cbNamespaces.SelectedIndex != 0)
				filters[index++] = new LogFilter(FilterType.Namespace, cbNamespaces.SelectedItem.ToString());

			if (cbLogLevel.SelectedIndex != 0)
			{
				filters[index++] = new LogFilter(FilterType.LogLevel, 
					cbLogLevel.SelectedIndex + 1);
			}

			ClearGridContents();

			FlashLogEntryCollection filtered = m_entries.GetFilteredSet(filters);

			foreach (FlashLogEntry e in filtered)
			{
				AddLogEntryToGrid(e);
			}
		}

		#endregion

		#region Event Handlers

		/// <summary>
		/// Fired when the LogEntries collection has a class added.
		/// 
		/// This has the effect of adding the class to the filter dropdown.
		/// </summary>
		/// <param name="collection"></param>
		/// <param name="newClass"></param>
		private void Log_ClassAdded(FlashLogEntryCollection collection, string newClass)
		{
			this.cbClasses.Items.Add(newClass);
		}


		/// <summary>
		/// Fired when the LogEntries collection has a namespace added.
		/// 
		/// This has the effect of adding the namespace to the filter dropdown.
		/// </summary>
		/// <param name="collection"></param>
		/// <param name="newNamespace"></param>
		private void Log_NamespaceAdded(FlashLogEntryCollection collection, string newNamespace)
		{
			this.cbNamespaces.Items.Add(newNamespace);
		}


		/// <summary>
		/// Fired when the Log collection adds an entry.
		/// </summary>
		/// <param name="collection"></param>
		/// <param name="newEntry"></param>
		private void Log_EntryAdded(FlashLogEntryCollection collection, FlashLogEntry newEntry)
		{
			m_entries.Add(newEntry);
			gridLog.Invoke(new ObjectEventHandler(AddLogEntryToGrid), new object[1] {newEntry});
		}

		/// <summary>
		/// Fired when layout should be performed on the form.
		/// </summary>
		/// <param name="sender"></param>
		/// <param name="e"></param>
		private void ServerForm_Layout(object sender, LayoutEventArgs e)
		{
			SuspendLayout();
			PerformLayout();
			ResumeLayout();
		}


		/// <summary>
		/// Sets the currently selected log entry and enables the properties
		/// button.
		/// </summary>
		/// <param name="sender"></param>
		/// <param name="e"></param>
		private void gridLog_FocusRowEntered(object sender, SourceGrid2.RowEventArgs e)
		{
			btnProperties.Enabled = gridLog.Selection.SelectedRows.Length == 1;

			m_selectedentry = (FlashLogEntry) e.Row.Tag;

			
		}


		/// <summary>
		/// Clears the grid.
		/// </summary>
		/// <param name="sender"></param>
		/// <param name="e"></param>
		private void btnClear_Click(object sender, System.EventArgs e)
		{
			ClearGridContents();
			m_entries.Clear();
		}


		/// <summary>
		/// Launches the about dialog.
		/// </summary>
		/// <param name="sender"></param>
		/// <param name="e"></param>
		private void miAbout_Click(object sender, System.EventArgs e)
		{
			AboutForm aboutForm = new AboutForm();
			aboutForm.ShowDialog(this);
		}


		/// <summary>
		/// Launces the properties dialog for the currently selected
		/// entry.
		/// </summary>
		/// <param name="sender"></param>
		/// <param name="e"></param>
		private void btnProperties_Click(object sender, System.EventArgs e)
		{
			if (m_selectedentry == null)
				throw new InvalidOperationException("Cannot view properties when no row is selected");

			frmProperties.LogEntry = m_selectedentry;
			frmProperties.ShowDialog();
		}

		private void cbLogLevel_SelectedIndexChanged(object sender, System.EventArgs e)
		{
			ApplyFiltersAndDisplay();
		}

		private void cbNamespaces_SelectedIndexChanged(object sender, System.EventArgs e)
		{
			ApplyFiltersAndDisplay();
		}

		private void cbClasses_SelectedIndexChanged(object sender, System.EventArgs e)
		{
			ApplyFiltersAndDisplay();
		}

		#endregion



	}
}
