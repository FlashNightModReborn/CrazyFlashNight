using System;
using System.Drawing;
using System.Collections;
using System.ComponentModel;
using System.Windows.Forms;

namespace FlashSocketServer
{
	/// <summary>
	/// Summary description for AboutForm.
	/// </summary>
	public class AboutForm : System.Windows.Forms.Form
	{
		private System.Windows.Forms.Label label1;
		private System.Windows.Forms.Label label2;
		private System.Windows.Forms.Label lblAuthor;
		private System.Windows.Forms.Label lblAuthorEmail;
		private System.Windows.Forms.LinkLabel linkAuthorEmail;
		private System.Windows.Forms.LinkLabel linkProjectWebsite;
		private System.Windows.Forms.Panel panel1;
		/// <summary>
		/// Required designer variable.
		/// </summary>
		private System.ComponentModel.Container components = null;

		public AboutForm()
		{
			//
			// Required for Windows Form Designer support
			//
			InitializeComponent();

			//
			// TODO: Add any constructor code after InitializeComponent call
			//
		}

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

		#region Windows Form Designer generated code
		/// <summary>
		/// Required method for Designer support - do not modify
		/// the contents of this method with the code editor.
		/// </summary>
		private void InitializeComponent()
		{
			System.Resources.ResourceManager resources = new System.Resources.ResourceManager(typeof(AboutForm));
			this.label1 = new System.Windows.Forms.Label();
			this.label2 = new System.Windows.Forms.Label();
			this.lblAuthor = new System.Windows.Forms.Label();
			this.lblAuthorEmail = new System.Windows.Forms.Label();
			this.linkAuthorEmail = new System.Windows.Forms.LinkLabel();
			this.linkProjectWebsite = new System.Windows.Forms.LinkLabel();
			this.panel1 = new System.Windows.Forms.Panel();
			this.panel1.SuspendLayout();
			this.SuspendLayout();
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
			this.label1.ForeColor = System.Drawing.Color.MediumBlue;
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
			// label2
			// 
			this.label2.AccessibleDescription = ((string)(resources.GetObject("label2.AccessibleDescription")));
			this.label2.AccessibleName = ((string)(resources.GetObject("label2.AccessibleName")));
			this.label2.Anchor = ((System.Windows.Forms.AnchorStyles)(resources.GetObject("label2.Anchor")));
			this.label2.AutoSize = ((bool)(resources.GetObject("label2.AutoSize")));
			this.label2.Dock = ((System.Windows.Forms.DockStyle)(resources.GetObject("label2.Dock")));
			this.label2.Enabled = ((bool)(resources.GetObject("label2.Enabled")));
			this.label2.Font = ((System.Drawing.Font)(resources.GetObject("label2.Font")));
			this.label2.ForeColor = System.Drawing.SystemColors.ControlDark;
			this.label2.Image = ((System.Drawing.Image)(resources.GetObject("label2.Image")));
			this.label2.ImageAlign = ((System.Drawing.ContentAlignment)(resources.GetObject("label2.ImageAlign")));
			this.label2.ImageIndex = ((int)(resources.GetObject("label2.ImageIndex")));
			this.label2.ImeMode = ((System.Windows.Forms.ImeMode)(resources.GetObject("label2.ImeMode")));
			this.label2.Location = ((System.Drawing.Point)(resources.GetObject("label2.Location")));
			this.label2.Name = "label2";
			this.label2.RightToLeft = ((System.Windows.Forms.RightToLeft)(resources.GetObject("label2.RightToLeft")));
			this.label2.Size = ((System.Drawing.Size)(resources.GetObject("label2.Size")));
			this.label2.TabIndex = ((int)(resources.GetObject("label2.TabIndex")));
			this.label2.Text = resources.GetString("label2.Text");
			this.label2.TextAlign = ((System.Drawing.ContentAlignment)(resources.GetObject("label2.TextAlign")));
			this.label2.Visible = ((bool)(resources.GetObject("label2.Visible")));
			// 
			// lblAuthor
			// 
			this.lblAuthor.AccessibleDescription = ((string)(resources.GetObject("lblAuthor.AccessibleDescription")));
			this.lblAuthor.AccessibleName = ((string)(resources.GetObject("lblAuthor.AccessibleName")));
			this.lblAuthor.Anchor = ((System.Windows.Forms.AnchorStyles)(resources.GetObject("lblAuthor.Anchor")));
			this.lblAuthor.AutoSize = ((bool)(resources.GetObject("lblAuthor.AutoSize")));
			this.lblAuthor.Dock = ((System.Windows.Forms.DockStyle)(resources.GetObject("lblAuthor.Dock")));
			this.lblAuthor.Enabled = ((bool)(resources.GetObject("lblAuthor.Enabled")));
			this.lblAuthor.Font = ((System.Drawing.Font)(resources.GetObject("lblAuthor.Font")));
			this.lblAuthor.Image = ((System.Drawing.Image)(resources.GetObject("lblAuthor.Image")));
			this.lblAuthor.ImageAlign = ((System.Drawing.ContentAlignment)(resources.GetObject("lblAuthor.ImageAlign")));
			this.lblAuthor.ImageIndex = ((int)(resources.GetObject("lblAuthor.ImageIndex")));
			this.lblAuthor.ImeMode = ((System.Windows.Forms.ImeMode)(resources.GetObject("lblAuthor.ImeMode")));
			this.lblAuthor.Location = ((System.Drawing.Point)(resources.GetObject("lblAuthor.Location")));
			this.lblAuthor.Name = "lblAuthor";
			this.lblAuthor.RightToLeft = ((System.Windows.Forms.RightToLeft)(resources.GetObject("lblAuthor.RightToLeft")));
			this.lblAuthor.Size = ((System.Drawing.Size)(resources.GetObject("lblAuthor.Size")));
			this.lblAuthor.TabIndex = ((int)(resources.GetObject("lblAuthor.TabIndex")));
			this.lblAuthor.Text = resources.GetString("lblAuthor.Text");
			this.lblAuthor.TextAlign = ((System.Drawing.ContentAlignment)(resources.GetObject("lblAuthor.TextAlign")));
			this.lblAuthor.Visible = ((bool)(resources.GetObject("lblAuthor.Visible")));
			// 
			// lblAuthorEmail
			// 
			this.lblAuthorEmail.AccessibleDescription = ((string)(resources.GetObject("lblAuthorEmail.AccessibleDescription")));
			this.lblAuthorEmail.AccessibleName = ((string)(resources.GetObject("lblAuthorEmail.AccessibleName")));
			this.lblAuthorEmail.Anchor = ((System.Windows.Forms.AnchorStyles)(resources.GetObject("lblAuthorEmail.Anchor")));
			this.lblAuthorEmail.AutoSize = ((bool)(resources.GetObject("lblAuthorEmail.AutoSize")));
			this.lblAuthorEmail.Dock = ((System.Windows.Forms.DockStyle)(resources.GetObject("lblAuthorEmail.Dock")));
			this.lblAuthorEmail.Enabled = ((bool)(resources.GetObject("lblAuthorEmail.Enabled")));
			this.lblAuthorEmail.Font = ((System.Drawing.Font)(resources.GetObject("lblAuthorEmail.Font")));
			this.lblAuthorEmail.Image = ((System.Drawing.Image)(resources.GetObject("lblAuthorEmail.Image")));
			this.lblAuthorEmail.ImageAlign = ((System.Drawing.ContentAlignment)(resources.GetObject("lblAuthorEmail.ImageAlign")));
			this.lblAuthorEmail.ImageIndex = ((int)(resources.GetObject("lblAuthorEmail.ImageIndex")));
			this.lblAuthorEmail.ImeMode = ((System.Windows.Forms.ImeMode)(resources.GetObject("lblAuthorEmail.ImeMode")));
			this.lblAuthorEmail.Location = ((System.Drawing.Point)(resources.GetObject("lblAuthorEmail.Location")));
			this.lblAuthorEmail.Name = "lblAuthorEmail";
			this.lblAuthorEmail.RightToLeft = ((System.Windows.Forms.RightToLeft)(resources.GetObject("lblAuthorEmail.RightToLeft")));
			this.lblAuthorEmail.Size = ((System.Drawing.Size)(resources.GetObject("lblAuthorEmail.Size")));
			this.lblAuthorEmail.TabIndex = ((int)(resources.GetObject("lblAuthorEmail.TabIndex")));
			this.lblAuthorEmail.Text = resources.GetString("lblAuthorEmail.Text");
			this.lblAuthorEmail.TextAlign = ((System.Drawing.ContentAlignment)(resources.GetObject("lblAuthorEmail.TextAlign")));
			this.lblAuthorEmail.Visible = ((bool)(resources.GetObject("lblAuthorEmail.Visible")));
			// 
			// linkAuthorEmail
			// 
			this.linkAuthorEmail.AccessibleDescription = ((string)(resources.GetObject("linkAuthorEmail.AccessibleDescription")));
			this.linkAuthorEmail.AccessibleName = ((string)(resources.GetObject("linkAuthorEmail.AccessibleName")));
			this.linkAuthorEmail.Anchor = ((System.Windows.Forms.AnchorStyles)(resources.GetObject("linkAuthorEmail.Anchor")));
			this.linkAuthorEmail.AutoSize = ((bool)(resources.GetObject("linkAuthorEmail.AutoSize")));
			this.linkAuthorEmail.Dock = ((System.Windows.Forms.DockStyle)(resources.GetObject("linkAuthorEmail.Dock")));
			this.linkAuthorEmail.Enabled = ((bool)(resources.GetObject("linkAuthorEmail.Enabled")));
			this.linkAuthorEmail.Font = ((System.Drawing.Font)(resources.GetObject("linkAuthorEmail.Font")));
			this.linkAuthorEmail.Image = ((System.Drawing.Image)(resources.GetObject("linkAuthorEmail.Image")));
			this.linkAuthorEmail.ImageAlign = ((System.Drawing.ContentAlignment)(resources.GetObject("linkAuthorEmail.ImageAlign")));
			this.linkAuthorEmail.ImageIndex = ((int)(resources.GetObject("linkAuthorEmail.ImageIndex")));
			this.linkAuthorEmail.ImeMode = ((System.Windows.Forms.ImeMode)(resources.GetObject("linkAuthorEmail.ImeMode")));
			this.linkAuthorEmail.LinkArea = ((System.Windows.Forms.LinkArea)(resources.GetObject("linkAuthorEmail.LinkArea")));
			this.linkAuthorEmail.LinkBehavior = System.Windows.Forms.LinkBehavior.HoverUnderline;
			this.linkAuthorEmail.Location = ((System.Drawing.Point)(resources.GetObject("linkAuthorEmail.Location")));
			this.linkAuthorEmail.Name = "linkAuthorEmail";
			this.linkAuthorEmail.RightToLeft = ((System.Windows.Forms.RightToLeft)(resources.GetObject("linkAuthorEmail.RightToLeft")));
			this.linkAuthorEmail.Size = ((System.Drawing.Size)(resources.GetObject("linkAuthorEmail.Size")));
			this.linkAuthorEmail.TabIndex = ((int)(resources.GetObject("linkAuthorEmail.TabIndex")));
			this.linkAuthorEmail.TabStop = true;
			this.linkAuthorEmail.Text = resources.GetString("linkAuthorEmail.Text");
			this.linkAuthorEmail.TextAlign = ((System.Drawing.ContentAlignment)(resources.GetObject("linkAuthorEmail.TextAlign")));
			this.linkAuthorEmail.Visible = ((bool)(resources.GetObject("linkAuthorEmail.Visible")));
			this.linkAuthorEmail.LinkClicked += new System.Windows.Forms.LinkLabelLinkClickedEventHandler(this.linkAuthorEmail_LinkClicked);
			// 
			// linkProjectWebsite
			// 
			this.linkProjectWebsite.AccessibleDescription = ((string)(resources.GetObject("linkProjectWebsite.AccessibleDescription")));
			this.linkProjectWebsite.AccessibleName = ((string)(resources.GetObject("linkProjectWebsite.AccessibleName")));
			this.linkProjectWebsite.Anchor = ((System.Windows.Forms.AnchorStyles)(resources.GetObject("linkProjectWebsite.Anchor")));
			this.linkProjectWebsite.AutoSize = ((bool)(resources.GetObject("linkProjectWebsite.AutoSize")));
			this.linkProjectWebsite.Dock = ((System.Windows.Forms.DockStyle)(resources.GetObject("linkProjectWebsite.Dock")));
			this.linkProjectWebsite.Enabled = ((bool)(resources.GetObject("linkProjectWebsite.Enabled")));
			this.linkProjectWebsite.Font = ((System.Drawing.Font)(resources.GetObject("linkProjectWebsite.Font")));
			this.linkProjectWebsite.Image = ((System.Drawing.Image)(resources.GetObject("linkProjectWebsite.Image")));
			this.linkProjectWebsite.ImageAlign = ((System.Drawing.ContentAlignment)(resources.GetObject("linkProjectWebsite.ImageAlign")));
			this.linkProjectWebsite.ImageIndex = ((int)(resources.GetObject("linkProjectWebsite.ImageIndex")));
			this.linkProjectWebsite.ImeMode = ((System.Windows.Forms.ImeMode)(resources.GetObject("linkProjectWebsite.ImeMode")));
			this.linkProjectWebsite.LinkArea = ((System.Windows.Forms.LinkArea)(resources.GetObject("linkProjectWebsite.LinkArea")));
			this.linkProjectWebsite.LinkBehavior = System.Windows.Forms.LinkBehavior.HoverUnderline;
			this.linkProjectWebsite.Location = ((System.Drawing.Point)(resources.GetObject("linkProjectWebsite.Location")));
			this.linkProjectWebsite.Name = "linkProjectWebsite";
			this.linkProjectWebsite.RightToLeft = ((System.Windows.Forms.RightToLeft)(resources.GetObject("linkProjectWebsite.RightToLeft")));
			this.linkProjectWebsite.Size = ((System.Drawing.Size)(resources.GetObject("linkProjectWebsite.Size")));
			this.linkProjectWebsite.TabIndex = ((int)(resources.GetObject("linkProjectWebsite.TabIndex")));
			this.linkProjectWebsite.TabStop = true;
			this.linkProjectWebsite.Text = resources.GetString("linkProjectWebsite.Text");
			this.linkProjectWebsite.TextAlign = ((System.Drawing.ContentAlignment)(resources.GetObject("linkProjectWebsite.TextAlign")));
			this.linkProjectWebsite.Visible = ((bool)(resources.GetObject("linkProjectWebsite.Visible")));
			this.linkProjectWebsite.LinkClicked += new System.Windows.Forms.LinkLabelLinkClickedEventHandler(this.linkProjectWebsite_LinkClicked);
			// 
			// panel1
			// 
			this.panel1.AccessibleDescription = ((string)(resources.GetObject("panel1.AccessibleDescription")));
			this.panel1.AccessibleName = ((string)(resources.GetObject("panel1.AccessibleName")));
			this.panel1.Anchor = ((System.Windows.Forms.AnchorStyles)(resources.GetObject("panel1.Anchor")));
			this.panel1.AutoScroll = ((bool)(resources.GetObject("panel1.AutoScroll")));
			this.panel1.AutoScrollMargin = ((System.Drawing.Size)(resources.GetObject("panel1.AutoScrollMargin")));
			this.panel1.AutoScrollMinSize = ((System.Drawing.Size)(resources.GetObject("panel1.AutoScrollMinSize")));
			this.panel1.BackColor = System.Drawing.SystemColors.ControlLightLight;
			this.panel1.BackgroundImage = ((System.Drawing.Image)(resources.GetObject("panel1.BackgroundImage")));
			this.panel1.Controls.AddRange(new System.Windows.Forms.Control[] {
																				 this.label2,
																				 this.label1});
			this.panel1.Dock = ((System.Windows.Forms.DockStyle)(resources.GetObject("panel1.Dock")));
			this.panel1.Enabled = ((bool)(resources.GetObject("panel1.Enabled")));
			this.panel1.Font = ((System.Drawing.Font)(resources.GetObject("panel1.Font")));
			this.panel1.ImeMode = ((System.Windows.Forms.ImeMode)(resources.GetObject("panel1.ImeMode")));
			this.panel1.Location = ((System.Drawing.Point)(resources.GetObject("panel1.Location")));
			this.panel1.Name = "panel1";
			this.panel1.RightToLeft = ((System.Windows.Forms.RightToLeft)(resources.GetObject("panel1.RightToLeft")));
			this.panel1.Size = ((System.Drawing.Size)(resources.GetObject("panel1.Size")));
			this.panel1.TabIndex = ((int)(resources.GetObject("panel1.TabIndex")));
			this.panel1.Text = resources.GetString("panel1.Text");
			this.panel1.Visible = ((bool)(resources.GetObject("panel1.Visible")));
			// 
			// AboutForm
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
																		  this.linkProjectWebsite,
																		  this.linkAuthorEmail,
																		  this.lblAuthorEmail,
																		  this.lblAuthor,
																		  this.panel1});
			this.Dock = ((System.Windows.Forms.DockStyle)(resources.GetObject("$this.Dock")));
			this.Enabled = ((bool)(resources.GetObject("$this.Enabled")));
			this.Font = ((System.Drawing.Font)(resources.GetObject("$this.Font")));
			this.FormBorderStyle = System.Windows.Forms.FormBorderStyle.FixedSingle;
			this.Icon = ((System.Drawing.Icon)(resources.GetObject("$this.Icon")));
			this.ImeMode = ((System.Windows.Forms.ImeMode)(resources.GetObject("$this.ImeMode")));
			this.Location = ((System.Drawing.Point)(resources.GetObject("$this.Location")));
			this.MaximizeBox = false;
			this.MaximumSize = ((System.Drawing.Size)(resources.GetObject("$this.MaximumSize")));
			this.MinimizeBox = false;
			this.MinimumSize = ((System.Drawing.Size)(resources.GetObject("$this.MinimumSize")));
			this.Name = "AboutForm";
			this.RightToLeft = ((System.Windows.Forms.RightToLeft)(resources.GetObject("$this.RightToLeft")));
			this.ShowInTaskbar = false;
			this.StartPosition = ((System.Windows.Forms.FormStartPosition)(resources.GetObject("$this.StartPosition")));
			this.Text = resources.GetString("$this.Text");
			this.TopMost = true;
			this.Visible = ((bool)(resources.GetObject("$this.Visible")));
			this.panel1.ResumeLayout(false);
			this.ResumeLayout(false);

		}
		#endregion

		private void linkAuthorEmail_LinkClicked(object sender, System.Windows.Forms.LinkLabelLinkClickedEventArgs e)
		{
			System.Diagnostics.Process.Start("mailto:" + ((LinkLabel) sender).Text);
		}

		private void linkProjectWebsite_LinkClicked(object sender, System.Windows.Forms.LinkLabelLinkClickedEventArgs e)
		{
			System.Diagnostics.Process.Start(((LinkLabel) sender).Text);
		}
	}
}
