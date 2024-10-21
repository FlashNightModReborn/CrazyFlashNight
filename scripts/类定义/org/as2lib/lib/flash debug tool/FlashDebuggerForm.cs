using System;
using System.Drawing;
using System.Collections;
using System.ComponentModel;
using System.Windows.Forms;
using System.IO;
using FlashSocketServer.Communication;

namespace FlashSocketServer
{
	/// <summary>
	/// For connection status.
	/// </summary>
	enum LEDImageIndex : int
	{
		Blue = 0,
		Red = 1,
		Yellow = 2,
		Green = 3
	}
		
	/// <summary>
	/// Main form for the Flash Debug Tools application. This creates
	/// the socket and passes it to child forms.
	/// </summary>
	public class FlashDebuggerForm : System.Windows.Forms.Form
	{
		private const int DEFAULT_SOCKETPORT = 4500;

		//
		// Forms
		//
		private LoggerForm m_loggerform;
		private PropertyInspectorForm m_propinspectform;

		//
		// Member vars
		//
		private FlashSocket m_flashsocket;
		private int m_tab_delta_x;
		private int m_tab_delta_y;

		private System.Windows.Forms.TabControl tabSections;
		private System.Windows.Forms.TabPage tpgLogger;
		private System.Windows.Forms.GroupBox grpSettings;
		private System.Windows.Forms.Button btnListen;
		private System.Windows.Forms.TextBox txtPortNo;
		private System.Windows.Forms.Label label1;
		private System.Windows.Forms.TabPage tpgPropInspector;
		private System.Windows.Forms.Label lblConnectionStatus;
		private System.Windows.Forms.ImageList imageListLED;
		private System.Windows.Forms.MenuItem miHelp;
		private System.Windows.Forms.MenuItem miHelp_Contents;
		private System.Windows.Forms.MenuItem miHelp_Index;
		private System.Windows.Forms.MenuItem miHelp_Search;
		private System.Windows.Forms.MenuItem menuItem1;
		private System.Windows.Forms.MenuItem menuItem2;
		private System.Windows.Forms.MenuItem miFile;
		private System.Windows.Forms.MenuItem miFile_Settings;
		private System.Windows.Forms.MenuItem menuItem3;
		private System.Windows.Forms.MenuItem miFile_Exit;
		private System.Windows.Forms.PictureBox imgLED;
		private System.Windows.Forms.MainMenu mainMenu;
		private System.ComponentModel.IContainer components;

		public FlashDebuggerForm()
		{
			//
			// Required for Windows Form Designer support
			//
			InitializeComponent();

			//
			// Set defaults
			//
			txtPortNo.Text = DEFAULT_SOCKETPORT.ToString();

			//
			// Create necessary variables
			//
			m_flashsocket = new FlashSocket();
			m_flashsocket.ClientConnect += new FlashSocket.ClientConnectHandler(flashSocket_ClientConnect);
			m_flashsocket.ClientDisconnect += new EventHandler(flashSocket_ClientDisconnect);

			//
			// Layout variables
			//
			m_tab_delta_x = this.Width - tabSections.Width;
			m_tab_delta_y = this.Height - tabSections.Height;

			//
			// Create tabs
			//
			m_loggerform = new LoggerForm(m_flashsocket);
			tabSections.TabPages[0].Controls.Add(m_loggerform);

			m_propinspectform = new PropertyInspectorForm(m_flashsocket);
			tabSections.TabPages[1].Controls.Add(m_propinspectform);

			//
			// Set initial LED
			//
			SetLEDColour(LEDImageIndex.Red);

			//
			// User prefs
			//
			UserPreferences.Load();

			if (UserPreferences.Current.Port != 0)
				txtPortNo.Text = UserPreferences.Current.Port.ToString();

			if (UserPreferences.Current.WindowSize != System.Drawing.Rectangle.Empty)
				this.Bounds = UserPreferences.Current.WindowSize;

			//
			// Turn the socket on.
			//
			ToggleSocket();
		}

		#region Destructor

		/// <summary>
		/// Clean up any resources being used.
		/// </summary>
		protected override void Dispose( bool disposing )
		{
			if( disposing )
			{
				if(components != null)
				{
					components.Dispose();
				}
			}
			base.Dispose( disposing );
		}

		#endregion

		#region Properties

		public FlashSocket Socket
		{
			get
			{
				return m_flashsocket;
			}
		}

		#endregion

		#region Public Methods

		#endregion

		#region Protected Methods

		#endregion

		#region Private Methods

		private void SetLEDColour(LEDImageIndex index)
		{
			imgLED.Image = imageListLED.Images[(int) index];
		}

		private void ToggleSocket()
		{
			if (!m_flashsocket.IsAlive)
			{
				SetLEDColour(LEDImageIndex.Yellow);

				m_flashsocket.Port = Int32.Parse(txtPortNo.Text);
				m_flashsocket.CreateSocket();

				txtPortNo.Enabled = false;
				btnListen.Text = "Stop Listening";
			}
			else
			{
				SetLEDColour(LEDImageIndex.Red);

				m_flashsocket.KillSocket();
				txtPortNo.Enabled = true;
				btnListen.Text = "Start Listening";
			}
		}

		#endregion

		#region Event Handlers 

		/// <summary>
		/// Begins / stops listening to communications from Flash.
		/// </summary>
		/// <param name="sender"></param>
		/// <param name="e"></param>
		private void btnListen_Click(object sender, System.EventArgs e)
		{
			ToggleSocket();
		}

		private void flashSocket_ClientConnect(System.Net.Sockets.Socket s)
		{
			SetLEDColour(LEDImageIndex.Green);
		}

		private void flashSocket_ClientDisconnect(object sender, EventArgs e)
		{
			SetLEDColour(LEDImageIndex.Yellow);
		}

		/// <summary>
		/// Fired when the main form app closes.
		/// </summary>
		/// <param name="sender"></param>
		/// <param name="e"></param>
		private void FlashDebuggerForm_Closing(object sender, System.ComponentModel.CancelEventArgs e)
		{
			UserPreferences.Current.Port = int.Parse(txtPortNo.Text);
			UserPreferences.Current.WindowSize = this.Bounds;
			UserPreferences.Save();
			Application.Exit();
		}


		/// <summary>
		/// Lays out the dialog.
		/// </summary>
		/// <param name="sender"></param>
		/// <param name="e"></param>
		private void FlashDebuggerForm_Layout(object sender, System.Windows.Forms.LayoutEventArgs e)
		{
			SuspendLayout();

			int width = this.Width - m_tab_delta_x;
			int height = this.Height - m_tab_delta_y;
			
			tabSections.Width = width;
			tabSections.Height = height;  		
			m_loggerform.Width = m_propinspectform.Width = width - 8;
			m_loggerform.Height = m_propinspectform.Height = height - 32;

			imgLED.Location = new Point(this.Width - 8 - imgLED.Width, imgLED.Top);
			lblConnectionStatus.Location = new Point(imgLED.Left - lblConnectionStatus.Width,
				lblConnectionStatus.Top);

			ResumeLayout();
		}

		private void miAbout_Click(object sender, System.EventArgs e)
		{
			AboutForm about = new AboutForm();
			about.ShowDialog(this);
		}


		private void miFile_Exit_Click(object sender, System.EventArgs e)
		{
			this.Close();
		}

		#endregion

		#region Windows Form Designer generated code
		/// <summary>
		/// Required method for Designer support - do not modify
		/// the contents of this method with the code editor.
		/// </summary>
		private void InitializeComponent()
		{
			this.components = new System.ComponentModel.Container();
			System.Resources.ResourceManager resources = new System.Resources.ResourceManager(typeof(FlashDebuggerForm));
			this.tabSections = new System.Windows.Forms.TabControl();
			this.tpgLogger = new System.Windows.Forms.TabPage();
			this.tpgPropInspector = new System.Windows.Forms.TabPage();
			this.mainMenu = new System.Windows.Forms.MainMenu();
			this.miFile = new System.Windows.Forms.MenuItem();
			this.miFile_Settings = new System.Windows.Forms.MenuItem();
			this.menuItem3 = new System.Windows.Forms.MenuItem();
			this.miFile_Exit = new System.Windows.Forms.MenuItem();
			this.miHelp = new System.Windows.Forms.MenuItem();
			this.miHelp_Contents = new System.Windows.Forms.MenuItem();
			this.miHelp_Index = new System.Windows.Forms.MenuItem();
			this.miHelp_Search = new System.Windows.Forms.MenuItem();
			this.menuItem1 = new System.Windows.Forms.MenuItem();
			this.menuItem2 = new System.Windows.Forms.MenuItem();
			this.grpSettings = new System.Windows.Forms.GroupBox();
			this.btnListen = new System.Windows.Forms.Button();
			this.txtPortNo = new System.Windows.Forms.TextBox();
			this.label1 = new System.Windows.Forms.Label();
			this.lblConnectionStatus = new System.Windows.Forms.Label();
			this.imageListLED = new System.Windows.Forms.ImageList(this.components);
			this.imgLED = new System.Windows.Forms.PictureBox();
			this.tabSections.SuspendLayout();
			this.grpSettings.SuspendLayout();
			this.SuspendLayout();
			// 
			// tabSections
			// 
			this.tabSections.AccessibleDescription = ((string)(resources.GetObject("tabSections.AccessibleDescription")));
			this.tabSections.AccessibleName = ((string)(resources.GetObject("tabSections.AccessibleName")));
			this.tabSections.Alignment = ((System.Windows.Forms.TabAlignment)(resources.GetObject("tabSections.Alignment")));
			this.tabSections.Anchor = ((System.Windows.Forms.AnchorStyles)(resources.GetObject("tabSections.Anchor")));
			this.tabSections.Appearance = ((System.Windows.Forms.TabAppearance)(resources.GetObject("tabSections.Appearance")));
			this.tabSections.BackgroundImage = ((System.Drawing.Image)(resources.GetObject("tabSections.BackgroundImage")));
			this.tabSections.Controls.AddRange(new System.Windows.Forms.Control[] {
																					  this.tpgLogger,
																					  this.tpgPropInspector});
			this.tabSections.Dock = ((System.Windows.Forms.DockStyle)(resources.GetObject("tabSections.Dock")));
			this.tabSections.Enabled = ((bool)(resources.GetObject("tabSections.Enabled")));
			this.tabSections.Font = ((System.Drawing.Font)(resources.GetObject("tabSections.Font")));
			this.tabSections.ImeMode = ((System.Windows.Forms.ImeMode)(resources.GetObject("tabSections.ImeMode")));
			this.tabSections.ItemSize = ((System.Drawing.Size)(resources.GetObject("tabSections.ItemSize")));
			this.tabSections.Location = ((System.Drawing.Point)(resources.GetObject("tabSections.Location")));
			this.tabSections.Name = "tabSections";
			this.tabSections.Padding = ((System.Drawing.Point)(resources.GetObject("tabSections.Padding")));
			this.tabSections.RightToLeft = ((System.Windows.Forms.RightToLeft)(resources.GetObject("tabSections.RightToLeft")));
			this.tabSections.SelectedIndex = 0;
			this.tabSections.ShowToolTips = ((bool)(resources.GetObject("tabSections.ShowToolTips")));
			this.tabSections.Size = ((System.Drawing.Size)(resources.GetObject("tabSections.Size")));
			this.tabSections.TabIndex = ((int)(resources.GetObject("tabSections.TabIndex")));
			this.tabSections.Text = resources.GetString("tabSections.Text");
			this.tabSections.Visible = ((bool)(resources.GetObject("tabSections.Visible")));
			// 
			// tpgLogger
			// 
			this.tpgLogger.AccessibleDescription = ((string)(resources.GetObject("tpgLogger.AccessibleDescription")));
			this.tpgLogger.AccessibleName = ((string)(resources.GetObject("tpgLogger.AccessibleName")));
			this.tpgLogger.Anchor = ((System.Windows.Forms.AnchorStyles)(resources.GetObject("tpgLogger.Anchor")));
			this.tpgLogger.AutoScroll = ((bool)(resources.GetObject("tpgLogger.AutoScroll")));
			this.tpgLogger.AutoScrollMargin = ((System.Drawing.Size)(resources.GetObject("tpgLogger.AutoScrollMargin")));
			this.tpgLogger.AutoScrollMinSize = ((System.Drawing.Size)(resources.GetObject("tpgLogger.AutoScrollMinSize")));
			this.tpgLogger.BackgroundImage = ((System.Drawing.Image)(resources.GetObject("tpgLogger.BackgroundImage")));
			this.tpgLogger.Dock = ((System.Windows.Forms.DockStyle)(resources.GetObject("tpgLogger.Dock")));
			this.tpgLogger.Enabled = ((bool)(resources.GetObject("tpgLogger.Enabled")));
			this.tpgLogger.Font = ((System.Drawing.Font)(resources.GetObject("tpgLogger.Font")));
			this.tpgLogger.ImageIndex = ((int)(resources.GetObject("tpgLogger.ImageIndex")));
			this.tpgLogger.ImeMode = ((System.Windows.Forms.ImeMode)(resources.GetObject("tpgLogger.ImeMode")));
			this.tpgLogger.Location = ((System.Drawing.Point)(resources.GetObject("tpgLogger.Location")));
			this.tpgLogger.Name = "tpgLogger";
			this.tpgLogger.RightToLeft = ((System.Windows.Forms.RightToLeft)(resources.GetObject("tpgLogger.RightToLeft")));
			this.tpgLogger.Size = ((System.Drawing.Size)(resources.GetObject("tpgLogger.Size")));
			this.tpgLogger.TabIndex = ((int)(resources.GetObject("tpgLogger.TabIndex")));
			this.tpgLogger.Text = resources.GetString("tpgLogger.Text");
			this.tpgLogger.ToolTipText = resources.GetString("tpgLogger.ToolTipText");
			this.tpgLogger.Visible = ((bool)(resources.GetObject("tpgLogger.Visible")));
			// 
			// tpgPropInspector
			// 
			this.tpgPropInspector.AccessibleDescription = ((string)(resources.GetObject("tpgPropInspector.AccessibleDescription")));
			this.tpgPropInspector.AccessibleName = ((string)(resources.GetObject("tpgPropInspector.AccessibleName")));
			this.tpgPropInspector.Anchor = ((System.Windows.Forms.AnchorStyles)(resources.GetObject("tpgPropInspector.Anchor")));
			this.tpgPropInspector.AutoScroll = ((bool)(resources.GetObject("tpgPropInspector.AutoScroll")));
			this.tpgPropInspector.AutoScrollMargin = ((System.Drawing.Size)(resources.GetObject("tpgPropInspector.AutoScrollMargin")));
			this.tpgPropInspector.AutoScrollMinSize = ((System.Drawing.Size)(resources.GetObject("tpgPropInspector.AutoScrollMinSize")));
			this.tpgPropInspector.BackgroundImage = ((System.Drawing.Image)(resources.GetObject("tpgPropInspector.BackgroundImage")));
			this.tpgPropInspector.Dock = ((System.Windows.Forms.DockStyle)(resources.GetObject("tpgPropInspector.Dock")));
			this.tpgPropInspector.Enabled = ((bool)(resources.GetObject("tpgPropInspector.Enabled")));
			this.tpgPropInspector.Font = ((System.Drawing.Font)(resources.GetObject("tpgPropInspector.Font")));
			this.tpgPropInspector.ImageIndex = ((int)(resources.GetObject("tpgPropInspector.ImageIndex")));
			this.tpgPropInspector.ImeMode = ((System.Windows.Forms.ImeMode)(resources.GetObject("tpgPropInspector.ImeMode")));
			this.tpgPropInspector.Location = ((System.Drawing.Point)(resources.GetObject("tpgPropInspector.Location")));
			this.tpgPropInspector.Name = "tpgPropInspector";
			this.tpgPropInspector.RightToLeft = ((System.Windows.Forms.RightToLeft)(resources.GetObject("tpgPropInspector.RightToLeft")));
			this.tpgPropInspector.Size = ((System.Drawing.Size)(resources.GetObject("tpgPropInspector.Size")));
			this.tpgPropInspector.TabIndex = ((int)(resources.GetObject("tpgPropInspector.TabIndex")));
			this.tpgPropInspector.Text = resources.GetString("tpgPropInspector.Text");
			this.tpgPropInspector.ToolTipText = resources.GetString("tpgPropInspector.ToolTipText");
			this.tpgPropInspector.Visible = ((bool)(resources.GetObject("tpgPropInspector.Visible")));
			// 
			// mainMenu
			// 
			this.mainMenu.MenuItems.AddRange(new System.Windows.Forms.MenuItem[] {
																					 this.miFile,
																					 this.miHelp});
			this.mainMenu.RightToLeft = ((System.Windows.Forms.RightToLeft)(resources.GetObject("mainMenu.RightToLeft")));
			// 
			// miFile
			// 
			this.miFile.Enabled = ((bool)(resources.GetObject("miFile.Enabled")));
			this.miFile.Index = 0;
			this.miFile.MenuItems.AddRange(new System.Windows.Forms.MenuItem[] {
																				   this.miFile_Settings,
																				   this.menuItem3,
																				   this.miFile_Exit});
			this.miFile.Shortcut = ((System.Windows.Forms.Shortcut)(resources.GetObject("miFile.Shortcut")));
			this.miFile.ShowShortcut = ((bool)(resources.GetObject("miFile.ShowShortcut")));
			this.miFile.Text = resources.GetString("miFile.Text");
			this.miFile.Visible = ((bool)(resources.GetObject("miFile.Visible")));
			// 
			// miFile_Settings
			// 
			this.miFile_Settings.Enabled = ((bool)(resources.GetObject("miFile_Settings.Enabled")));
			this.miFile_Settings.Index = 0;
			this.miFile_Settings.Shortcut = ((System.Windows.Forms.Shortcut)(resources.GetObject("miFile_Settings.Shortcut")));
			this.miFile_Settings.ShowShortcut = ((bool)(resources.GetObject("miFile_Settings.ShowShortcut")));
			this.miFile_Settings.Text = resources.GetString("miFile_Settings.Text");
			this.miFile_Settings.Visible = ((bool)(resources.GetObject("miFile_Settings.Visible")));
			// 
			// menuItem3
			// 
			this.menuItem3.Enabled = ((bool)(resources.GetObject("menuItem3.Enabled")));
			this.menuItem3.Index = 1;
			this.menuItem3.Shortcut = ((System.Windows.Forms.Shortcut)(resources.GetObject("menuItem3.Shortcut")));
			this.menuItem3.ShowShortcut = ((bool)(resources.GetObject("menuItem3.ShowShortcut")));
			this.menuItem3.Text = resources.GetString("menuItem3.Text");
			this.menuItem3.Visible = ((bool)(resources.GetObject("menuItem3.Visible")));
			// 
			// miFile_Exit
			// 
			this.miFile_Exit.Enabled = ((bool)(resources.GetObject("miFile_Exit.Enabled")));
			this.miFile_Exit.Index = 2;
			this.miFile_Exit.Shortcut = ((System.Windows.Forms.Shortcut)(resources.GetObject("miFile_Exit.Shortcut")));
			this.miFile_Exit.ShowShortcut = ((bool)(resources.GetObject("miFile_Exit.ShowShortcut")));
			this.miFile_Exit.Text = resources.GetString("miFile_Exit.Text");
			this.miFile_Exit.Visible = ((bool)(resources.GetObject("miFile_Exit.Visible")));
			this.miFile_Exit.Click += new System.EventHandler(this.miFile_Exit_Click);
			// 
			// miHelp
			// 
			this.miHelp.Enabled = ((bool)(resources.GetObject("miHelp.Enabled")));
			this.miHelp.Index = 1;
			this.miHelp.MenuItems.AddRange(new System.Windows.Forms.MenuItem[] {
																				   this.miHelp_Contents,
																				   this.miHelp_Index,
																				   this.miHelp_Search,
																				   this.menuItem1,
																				   this.menuItem2});
			this.miHelp.Shortcut = ((System.Windows.Forms.Shortcut)(resources.GetObject("miHelp.Shortcut")));
			this.miHelp.ShowShortcut = ((bool)(resources.GetObject("miHelp.ShowShortcut")));
			this.miHelp.Text = resources.GetString("miHelp.Text");
			this.miHelp.Visible = ((bool)(resources.GetObject("miHelp.Visible")));
			// 
			// miHelp_Contents
			// 
			this.miHelp_Contents.Enabled = ((bool)(resources.GetObject("miHelp_Contents.Enabled")));
			this.miHelp_Contents.Index = 0;
			this.miHelp_Contents.Shortcut = ((System.Windows.Forms.Shortcut)(resources.GetObject("miHelp_Contents.Shortcut")));
			this.miHelp_Contents.ShowShortcut = ((bool)(resources.GetObject("miHelp_Contents.ShowShortcut")));
			this.miHelp_Contents.Text = resources.GetString("miHelp_Contents.Text");
			this.miHelp_Contents.Visible = ((bool)(resources.GetObject("miHelp_Contents.Visible")));
			// 
			// miHelp_Index
			// 
			this.miHelp_Index.Enabled = ((bool)(resources.GetObject("miHelp_Index.Enabled")));
			this.miHelp_Index.Index = 1;
			this.miHelp_Index.Shortcut = ((System.Windows.Forms.Shortcut)(resources.GetObject("miHelp_Index.Shortcut")));
			this.miHelp_Index.ShowShortcut = ((bool)(resources.GetObject("miHelp_Index.ShowShortcut")));
			this.miHelp_Index.Text = resources.GetString("miHelp_Index.Text");
			this.miHelp_Index.Visible = ((bool)(resources.GetObject("miHelp_Index.Visible")));
			// 
			// miHelp_Search
			// 
			this.miHelp_Search.Enabled = ((bool)(resources.GetObject("miHelp_Search.Enabled")));
			this.miHelp_Search.Index = 2;
			this.miHelp_Search.Shortcut = ((System.Windows.Forms.Shortcut)(resources.GetObject("miHelp_Search.Shortcut")));
			this.miHelp_Search.ShowShortcut = ((bool)(resources.GetObject("miHelp_Search.ShowShortcut")));
			this.miHelp_Search.Text = resources.GetString("miHelp_Search.Text");
			this.miHelp_Search.Visible = ((bool)(resources.GetObject("miHelp_Search.Visible")));
			// 
			// menuItem1
			// 
			this.menuItem1.Enabled = ((bool)(resources.GetObject("menuItem1.Enabled")));
			this.menuItem1.Index = 3;
			this.menuItem1.Shortcut = ((System.Windows.Forms.Shortcut)(resources.GetObject("menuItem1.Shortcut")));
			this.menuItem1.ShowShortcut = ((bool)(resources.GetObject("menuItem1.ShowShortcut")));
			this.menuItem1.Text = resources.GetString("menuItem1.Text");
			this.menuItem1.Visible = ((bool)(resources.GetObject("menuItem1.Visible")));
			// 
			// menuItem2
			// 
			this.menuItem2.Enabled = ((bool)(resources.GetObject("menuItem2.Enabled")));
			this.menuItem2.Index = 4;
			this.menuItem2.Shortcut = ((System.Windows.Forms.Shortcut)(resources.GetObject("menuItem2.Shortcut")));
			this.menuItem2.ShowShortcut = ((bool)(resources.GetObject("menuItem2.ShowShortcut")));
			this.menuItem2.Text = resources.GetString("menuItem2.Text");
			this.menuItem2.Visible = ((bool)(resources.GetObject("menuItem2.Visible")));
			this.menuItem2.Click += new System.EventHandler(this.miAbout_Click);
			// 
			// grpSettings
			// 
			this.grpSettings.AccessibleDescription = ((string)(resources.GetObject("grpSettings.AccessibleDescription")));
			this.grpSettings.AccessibleName = ((string)(resources.GetObject("grpSettings.AccessibleName")));
			this.grpSettings.Anchor = ((System.Windows.Forms.AnchorStyles)(resources.GetObject("grpSettings.Anchor")));
			this.grpSettings.BackgroundImage = ((System.Drawing.Image)(resources.GetObject("grpSettings.BackgroundImage")));
			this.grpSettings.Controls.AddRange(new System.Windows.Forms.Control[] {
																					  this.btnListen,
																					  this.txtPortNo,
																					  this.label1});
			this.grpSettings.Dock = ((System.Windows.Forms.DockStyle)(resources.GetObject("grpSettings.Dock")));
			this.grpSettings.Enabled = ((bool)(resources.GetObject("grpSettings.Enabled")));
			this.grpSettings.Font = ((System.Drawing.Font)(resources.GetObject("grpSettings.Font")));
			this.grpSettings.ImeMode = ((System.Windows.Forms.ImeMode)(resources.GetObject("grpSettings.ImeMode")));
			this.grpSettings.Location = ((System.Drawing.Point)(resources.GetObject("grpSettings.Location")));
			this.grpSettings.Name = "grpSettings";
			this.grpSettings.RightToLeft = ((System.Windows.Forms.RightToLeft)(resources.GetObject("grpSettings.RightToLeft")));
			this.grpSettings.Size = ((System.Drawing.Size)(resources.GetObject("grpSettings.Size")));
			this.grpSettings.TabIndex = ((int)(resources.GetObject("grpSettings.TabIndex")));
			this.grpSettings.TabStop = false;
			this.grpSettings.Text = resources.GetString("grpSettings.Text");
			this.grpSettings.Visible = ((bool)(resources.GetObject("grpSettings.Visible")));
			// 
			// btnListen
			// 
			this.btnListen.AccessibleDescription = ((string)(resources.GetObject("btnListen.AccessibleDescription")));
			this.btnListen.AccessibleName = ((string)(resources.GetObject("btnListen.AccessibleName")));
			this.btnListen.Anchor = ((System.Windows.Forms.AnchorStyles)(resources.GetObject("btnListen.Anchor")));
			this.btnListen.BackgroundImage = ((System.Drawing.Image)(resources.GetObject("btnListen.BackgroundImage")));
			this.btnListen.Dock = ((System.Windows.Forms.DockStyle)(resources.GetObject("btnListen.Dock")));
			this.btnListen.Enabled = ((bool)(resources.GetObject("btnListen.Enabled")));
			this.btnListen.FlatStyle = ((System.Windows.Forms.FlatStyle)(resources.GetObject("btnListen.FlatStyle")));
			this.btnListen.Font = ((System.Drawing.Font)(resources.GetObject("btnListen.Font")));
			this.btnListen.Image = ((System.Drawing.Image)(resources.GetObject("btnListen.Image")));
			this.btnListen.ImageAlign = ((System.Drawing.ContentAlignment)(resources.GetObject("btnListen.ImageAlign")));
			this.btnListen.ImageIndex = ((int)(resources.GetObject("btnListen.ImageIndex")));
			this.btnListen.ImeMode = ((System.Windows.Forms.ImeMode)(resources.GetObject("btnListen.ImeMode")));
			this.btnListen.Location = ((System.Drawing.Point)(resources.GetObject("btnListen.Location")));
			this.btnListen.Name = "btnListen";
			this.btnListen.RightToLeft = ((System.Windows.Forms.RightToLeft)(resources.GetObject("btnListen.RightToLeft")));
			this.btnListen.Size = ((System.Drawing.Size)(resources.GetObject("btnListen.Size")));
			this.btnListen.TabIndex = ((int)(resources.GetObject("btnListen.TabIndex")));
			this.btnListen.Text = resources.GetString("btnListen.Text");
			this.btnListen.TextAlign = ((System.Drawing.ContentAlignment)(resources.GetObject("btnListen.TextAlign")));
			this.btnListen.Visible = ((bool)(resources.GetObject("btnListen.Visible")));
			this.btnListen.Click += new System.EventHandler(this.btnListen_Click);
			// 
			// txtPortNo
			// 
			this.txtPortNo.AccessibleDescription = ((string)(resources.GetObject("txtPortNo.AccessibleDescription")));
			this.txtPortNo.AccessibleName = ((string)(resources.GetObject("txtPortNo.AccessibleName")));
			this.txtPortNo.Anchor = ((System.Windows.Forms.AnchorStyles)(resources.GetObject("txtPortNo.Anchor")));
			this.txtPortNo.AutoSize = ((bool)(resources.GetObject("txtPortNo.AutoSize")));
			this.txtPortNo.BackgroundImage = ((System.Drawing.Image)(resources.GetObject("txtPortNo.BackgroundImage")));
			this.txtPortNo.Dock = ((System.Windows.Forms.DockStyle)(resources.GetObject("txtPortNo.Dock")));
			this.txtPortNo.Enabled = ((bool)(resources.GetObject("txtPortNo.Enabled")));
			this.txtPortNo.Font = ((System.Drawing.Font)(resources.GetObject("txtPortNo.Font")));
			this.txtPortNo.ImeMode = ((System.Windows.Forms.ImeMode)(resources.GetObject("txtPortNo.ImeMode")));
			this.txtPortNo.Location = ((System.Drawing.Point)(resources.GetObject("txtPortNo.Location")));
			this.txtPortNo.MaxLength = ((int)(resources.GetObject("txtPortNo.MaxLength")));
			this.txtPortNo.Multiline = ((bool)(resources.GetObject("txtPortNo.Multiline")));
			this.txtPortNo.Name = "txtPortNo";
			this.txtPortNo.PasswordChar = ((char)(resources.GetObject("txtPortNo.PasswordChar")));
			this.txtPortNo.RightToLeft = ((System.Windows.Forms.RightToLeft)(resources.GetObject("txtPortNo.RightToLeft")));
			this.txtPortNo.ScrollBars = ((System.Windows.Forms.ScrollBars)(resources.GetObject("txtPortNo.ScrollBars")));
			this.txtPortNo.Size = ((System.Drawing.Size)(resources.GetObject("txtPortNo.Size")));
			this.txtPortNo.TabIndex = ((int)(resources.GetObject("txtPortNo.TabIndex")));
			this.txtPortNo.Text = resources.GetString("txtPortNo.Text");
			this.txtPortNo.TextAlign = ((System.Windows.Forms.HorizontalAlignment)(resources.GetObject("txtPortNo.TextAlign")));
			this.txtPortNo.Visible = ((bool)(resources.GetObject("txtPortNo.Visible")));
			this.txtPortNo.WordWrap = ((bool)(resources.GetObject("txtPortNo.WordWrap")));
			// 
			// label1
			// 
			this.label1.AccessibleDescription = ((string)(resources.GetObject("label1.AccessibleDescription")));
			this.label1.AccessibleName = ((string)(resources.GetObject("label1.AccessibleName")));
			this.label1.Anchor = ((System.Windows.Forms.AnchorStyles)(resources.GetObject("label1.Anchor")));
			this.label1.AutoSize = ((bool)(resources.GetObject("label1.AutoSize")));
			this.label1.Dock = ((System.Windows.Forms.DockStyle)(resources.GetObject("label1.Dock")));
			this.label1.Enabled = ((bool)(resources.GetObject("label1.Enabled")));
			this.label1.Font = ((System.Drawing.Font)(resources.GetObject("label1.Font")));
			this.label1.Image = ((System.Drawing.Image)(resources.GetObject("label1.Image")));
			this.label1.ImageAlign = ((System.Drawing.ContentAlignment)(resources.GetObject("label1.ImageAlign")));
			this.label1.ImageIndex = ((int)(resources.GetObject("label1.ImageIndex")));
			this.label1.ImeMode = ((System.Windows.Forms.ImeMode)(resources.GetObject("label1.ImeMode")));
			this.label1.Location = ((System.Drawing.Point)(resources.GetObject("label1.Location")));
			this.label1.Name = "label1";
			this.label1.RightToLeft = ((System.Windows.Forms.RightToLeft)(resources.GetObject("label1.RightToLeft")));
			this.label1.Size = ((System.Drawing.Size)(resources.GetObject("label1.Size")));
			this.label1.TabIndex = ((int)(resources.GetObject("label1.TabIndex")));
			this.label1.Text = resources.GetString("label1.Text");
			this.label1.TextAlign = ((System.Drawing.ContentAlignment)(resources.GetObject("label1.TextAlign")));
			this.label1.Visible = ((bool)(resources.GetObject("label1.Visible")));
			// 
			// lblConnectionStatus
			// 
			this.lblConnectionStatus.AccessibleDescription = ((string)(resources.GetObject("lblConnectionStatus.AccessibleDescription")));
			this.lblConnectionStatus.AccessibleName = ((string)(resources.GetObject("lblConnectionStatus.AccessibleName")));
			this.lblConnectionStatus.Anchor = ((System.Windows.Forms.AnchorStyles)(resources.GetObject("lblConnectionStatus.Anchor")));
			this.lblConnectionStatus.AutoSize = ((bool)(resources.GetObject("lblConnectionStatus.AutoSize")));
			this.lblConnectionStatus.Dock = ((System.Windows.Forms.DockStyle)(resources.GetObject("lblConnectionStatus.Dock")));
			this.lblConnectionStatus.Enabled = ((bool)(resources.GetObject("lblConnectionStatus.Enabled")));
			this.lblConnectionStatus.Font = ((System.Drawing.Font)(resources.GetObject("lblConnectionStatus.Font")));
			this.lblConnectionStatus.Image = ((System.Drawing.Image)(resources.GetObject("lblConnectionStatus.Image")));
			this.lblConnectionStatus.ImageAlign = ((System.Drawing.ContentAlignment)(resources.GetObject("lblConnectionStatus.ImageAlign")));
			this.lblConnectionStatus.ImageIndex = ((int)(resources.GetObject("lblConnectionStatus.ImageIndex")));
			this.lblConnectionStatus.ImeMode = ((System.Windows.Forms.ImeMode)(resources.GetObject("lblConnectionStatus.ImeMode")));
			this.lblConnectionStatus.Location = ((System.Drawing.Point)(resources.GetObject("lblConnectionStatus.Location")));
			this.lblConnectionStatus.Name = "lblConnectionStatus";
			this.lblConnectionStatus.RightToLeft = ((System.Windows.Forms.RightToLeft)(resources.GetObject("lblConnectionStatus.RightToLeft")));
			this.lblConnectionStatus.Size = ((System.Drawing.Size)(resources.GetObject("lblConnectionStatus.Size")));
			this.lblConnectionStatus.TabIndex = ((int)(resources.GetObject("lblConnectionStatus.TabIndex")));
			this.lblConnectionStatus.Text = resources.GetString("lblConnectionStatus.Text");
			this.lblConnectionStatus.TextAlign = ((System.Drawing.ContentAlignment)(resources.GetObject("lblConnectionStatus.TextAlign")));
			this.lblConnectionStatus.Visible = ((bool)(resources.GetObject("lblConnectionStatus.Visible")));
			// 
			// imageListLED
			// 
			this.imageListLED.ColorDepth = System.Windows.Forms.ColorDepth.Depth8Bit;
			this.imageListLED.ImageSize = ((System.Drawing.Size)(resources.GetObject("imageListLED.ImageSize")));
			this.imageListLED.ImageStream = ((System.Windows.Forms.ImageListStreamer)(resources.GetObject("imageListLED.ImageStream")));
			this.imageListLED.TransparentColor = System.Drawing.Color.Transparent;
			// 
			// imgLED
			// 
			this.imgLED.AccessibleDescription = ((string)(resources.GetObject("imgLED.AccessibleDescription")));
			this.imgLED.AccessibleName = ((string)(resources.GetObject("imgLED.AccessibleName")));
			this.imgLED.Anchor = ((System.Windows.Forms.AnchorStyles)(resources.GetObject("imgLED.Anchor")));
			this.imgLED.BackgroundImage = ((System.Drawing.Image)(resources.GetObject("imgLED.BackgroundImage")));
			this.imgLED.Dock = ((System.Windows.Forms.DockStyle)(resources.GetObject("imgLED.Dock")));
			this.imgLED.Enabled = ((bool)(resources.GetObject("imgLED.Enabled")));
			this.imgLED.Font = ((System.Drawing.Font)(resources.GetObject("imgLED.Font")));
			this.imgLED.Image = ((System.Drawing.Image)(resources.GetObject("imgLED.Image")));
			this.imgLED.ImeMode = ((System.Windows.Forms.ImeMode)(resources.GetObject("imgLED.ImeMode")));
			this.imgLED.Location = ((System.Drawing.Point)(resources.GetObject("imgLED.Location")));
			this.imgLED.Name = "imgLED";
			this.imgLED.RightToLeft = ((System.Windows.Forms.RightToLeft)(resources.GetObject("imgLED.RightToLeft")));
			this.imgLED.Size = ((System.Drawing.Size)(resources.GetObject("imgLED.Size")));
			this.imgLED.SizeMode = ((System.Windows.Forms.PictureBoxSizeMode)(resources.GetObject("imgLED.SizeMode")));
			this.imgLED.TabIndex = ((int)(resources.GetObject("imgLED.TabIndex")));
			this.imgLED.TabStop = false;
			this.imgLED.Text = resources.GetString("imgLED.Text");
			this.imgLED.Visible = ((bool)(resources.GetObject("imgLED.Visible")));
			// 
			// FlashDebuggerForm
			// 
			this.AccessibleDescription = ((string)(resources.GetObject("$this.AccessibleDescription")));
			this.AccessibleName = ((string)(resources.GetObject("$this.AccessibleName")));
			this.Anchor = ((System.Windows.Forms.AnchorStyles)(resources.GetObject("$this.Anchor")));
			this.AutoScaleBaseSize = ((System.Drawing.Size)(resources.GetObject("$this.AutoScaleBaseSize")));
			this.AutoScroll = ((bool)(resources.GetObject("$this.AutoScroll")));
			this.AutoScrollMargin = ((System.Drawing.Size)(resources.GetObject("$this.AutoScrollMargin")));
			this.AutoScrollMinSize = ((System.Drawing.Size)(resources.GetObject("$this.AutoScrollMinSize")));
			this.BackgroundImage = ((System.Drawing.Image)(resources.GetObject("$this.BackgroundImage")));
			this.ClientSize = ((System.Drawing.Size)(resources.GetObject("$this.ClientSize")));
			this.Controls.AddRange(new System.Windows.Forms.Control[] {
																		  this.imgLED,
																		  this.lblConnectionStatus,
																		  this.grpSettings,
																		  this.tabSections});
			this.Dock = ((System.Windows.Forms.DockStyle)(resources.GetObject("$this.Dock")));
			this.Enabled = ((bool)(resources.GetObject("$this.Enabled")));
			this.Font = ((System.Drawing.Font)(resources.GetObject("$this.Font")));
			this.Icon = ((System.Drawing.Icon)(resources.GetObject("$this.Icon")));
			this.ImeMode = ((System.Windows.Forms.ImeMode)(resources.GetObject("$this.ImeMode")));
			this.Location = ((System.Drawing.Point)(resources.GetObject("$this.Location")));
			this.MaximumSize = ((System.Drawing.Size)(resources.GetObject("$this.MaximumSize")));
			this.Menu = this.mainMenu;
			this.MinimumSize = ((System.Drawing.Size)(resources.GetObject("$this.MinimumSize")));
			this.Name = "FlashDebuggerForm";
			this.RightToLeft = ((System.Windows.Forms.RightToLeft)(resources.GetObject("$this.RightToLeft")));
			this.SizeGripStyle = System.Windows.Forms.SizeGripStyle.Show;
			this.StartPosition = ((System.Windows.Forms.FormStartPosition)(resources.GetObject("$this.StartPosition")));
			this.Text = resources.GetString("$this.Text");
			this.Visible = ((bool)(resources.GetObject("$this.Visible")));
			this.Closing += new System.ComponentModel.CancelEventHandler(this.FlashDebuggerForm_Closing);
			this.Layout += new System.Windows.Forms.LayoutEventHandler(this.FlashDebuggerForm_Layout);
			this.tabSections.ResumeLayout(false);
			this.grpSettings.ResumeLayout(false);
			this.ResumeLayout(false);

		}
		#endregion

		#region Application Entry Point

		/// <summary>
		/// The main entry point for the application.
		/// </summary>
		[STAThread]
		static void Main() 
		{
			Application.Run(new FlashDebuggerForm());
		}

		#endregion






	}
}