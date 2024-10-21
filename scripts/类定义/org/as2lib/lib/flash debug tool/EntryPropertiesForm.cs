using System;
using System.Drawing;
using System.Collections;
using System.ComponentModel;
using System.Windows.Forms;
using FlashSocketServer.Log;

namespace FlashSocketServer
{
	/// <summary>
	/// Summary description for EntryPropertiesForm.
	/// </summary>
	public class EntryPropertiesForm : System.Windows.Forms.Form
	{
		private FlashLogEntry m_entry;

		private System.Windows.Forms.TextBox txtMessage;
		/// <summary>
		/// Required designer variable.
		/// </summary>
		private System.ComponentModel.Container components = null;

		public EntryPropertiesForm()
		{
			//
			// Required for Windows Form Designer support
			//
			InitializeComponent();
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

		public FlashLogEntry LogEntry
		{
			get
			{
				return m_entry;
			}
			set
			{
				m_entry = value;
				
				this.Text = "Log Entry Details - " + m_entry.TimeStamp.ToString("G");
				txtMessage.Text = m_entry.Message;
			}
		}

		#endregion

		#region Windows Form Designer generated code
		/// <summary>
		/// Required method for Designer support - do not modify
		/// the contents of this method with the code editor.
		/// </summary>
		private void InitializeComponent()
		{
			System.Resources.ResourceManager resources = new System.Resources.ResourceManager(typeof(EntryPropertiesForm));
			this.txtMessage = new System.Windows.Forms.TextBox();
			this.SuspendLayout();
			// 
			// txtMessage
			// 
			this.txtMessage.AccessibleDescription = ((string)(resources.GetObject("txtMessage.AccessibleDescription")));
			this.txtMessage.AccessibleName = ((string)(resources.GetObject("txtMessage.AccessibleName")));
			this.txtMessage.Anchor = ((System.Windows.Forms.AnchorStyles)(resources.GetObject("txtMessage.Anchor")));
			this.txtMessage.AutoSize = ((bool)(resources.GetObject("txtMessage.AutoSize")));
			this.txtMessage.BackgroundImage = ((System.Drawing.Image)(resources.GetObject("txtMessage.BackgroundImage")));
			this.txtMessage.Dock = ((System.Windows.Forms.DockStyle)(resources.GetObject("txtMessage.Dock")));
			this.txtMessage.Enabled = ((bool)(resources.GetObject("txtMessage.Enabled")));
			this.txtMessage.Font = ((System.Drawing.Font)(resources.GetObject("txtMessage.Font")));
			this.txtMessage.ImeMode = ((System.Windows.Forms.ImeMode)(resources.GetObject("txtMessage.ImeMode")));
			this.txtMessage.Location = ((System.Drawing.Point)(resources.GetObject("txtMessage.Location")));
			this.txtMessage.MaxLength = ((int)(resources.GetObject("txtMessage.MaxLength")));
			this.txtMessage.Multiline = ((bool)(resources.GetObject("txtMessage.Multiline")));
			this.txtMessage.Name = "txtMessage";
			this.txtMessage.PasswordChar = ((char)(resources.GetObject("txtMessage.PasswordChar")));
			this.txtMessage.RightToLeft = ((System.Windows.Forms.RightToLeft)(resources.GetObject("txtMessage.RightToLeft")));
			this.txtMessage.ScrollBars = ((System.Windows.Forms.ScrollBars)(resources.GetObject("txtMessage.ScrollBars")));
			this.txtMessage.Size = ((System.Drawing.Size)(resources.GetObject("txtMessage.Size")));
			this.txtMessage.TabIndex = ((int)(resources.GetObject("txtMessage.TabIndex")));
			this.txtMessage.Text = resources.GetString("txtMessage.Text");
			this.txtMessage.TextAlign = ((System.Windows.Forms.HorizontalAlignment)(resources.GetObject("txtMessage.TextAlign")));
			this.txtMessage.Visible = ((bool)(resources.GetObject("txtMessage.Visible")));
			this.txtMessage.WordWrap = ((bool)(resources.GetObject("txtMessage.WordWrap")));
			// 
			// EntryPropertiesForm
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
																		  this.txtMessage});
			this.Dock = ((System.Windows.Forms.DockStyle)(resources.GetObject("$this.Dock")));
			this.Enabled = ((bool)(resources.GetObject("$this.Enabled")));
			this.Font = ((System.Drawing.Font)(resources.GetObject("$this.Font")));
			this.Icon = ((System.Drawing.Icon)(resources.GetObject("$this.Icon")));
			this.ImeMode = ((System.Windows.Forms.ImeMode)(resources.GetObject("$this.ImeMode")));
			this.Location = ((System.Drawing.Point)(resources.GetObject("$this.Location")));
			this.MaximumSize = ((System.Drawing.Size)(resources.GetObject("$this.MaximumSize")));
			this.MinimumSize = ((System.Drawing.Size)(resources.GetObject("$this.MinimumSize")));
			this.Name = "EntryPropertiesForm";
			this.RightToLeft = ((System.Windows.Forms.RightToLeft)(resources.GetObject("$this.RightToLeft")));
			this.StartPosition = ((System.Windows.Forms.FormStartPosition)(resources.GetObject("$this.StartPosition")));
			this.Text = resources.GetString("$this.Text");
			this.Visible = ((bool)(resources.GetObject("$this.Visible")));
			this.ResumeLayout(false);

		}
		#endregion
	}
}
