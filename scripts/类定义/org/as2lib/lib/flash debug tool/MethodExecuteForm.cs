using System;
using System.Drawing;
using System.Collections;
using System.ComponentModel;
using System.Windows.Forms;

namespace FlashSocketServer
{
	/// <summary>
	/// Summary description for MethodExecuteForm.
	/// </summary>
	public class MethodExecuteForm : System.Windows.Forms.Form
	{
		private System.Windows.Forms.Button btnOK;
		private System.Windows.Forms.Button btnCancel;
		private System.Windows.Forms.ListBox lstArgs;
		private System.Windows.Forms.Button btnArgUp;
		private System.Windows.Forms.Button btnArgDown;
		private System.Windows.Forms.Label lblArgs;
		/// <summary>
		/// Required designer variable.
		/// </summary>
		private System.ComponentModel.Container components = null;

		public MethodExecuteForm()
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
			System.Resources.ResourceManager resources = new System.Resources.ResourceManager(typeof(MethodExecuteForm));
			this.btnOK = new System.Windows.Forms.Button();
			this.btnCancel = new System.Windows.Forms.Button();
			this.lstArgs = new System.Windows.Forms.ListBox();
			this.btnArgUp = new System.Windows.Forms.Button();
			this.btnArgDown = new System.Windows.Forms.Button();
			this.lblArgs = new System.Windows.Forms.Label();
			this.SuspendLayout();
			// 
			// btnOK
			// 
			this.btnOK.AccessibleDescription = ((string)(resources.GetObject("btnOK.AccessibleDescription")));
			this.btnOK.AccessibleName = ((string)(resources.GetObject("btnOK.AccessibleName")));
			this.btnOK.Anchor = ((System.Windows.Forms.AnchorStyles)(resources.GetObject("btnOK.Anchor")));
			this.btnOK.BackgroundImage = ((System.Drawing.Image)(resources.GetObject("btnOK.BackgroundImage")));
			this.btnOK.DialogResult = System.Windows.Forms.DialogResult.OK;
			this.btnOK.Dock = ((System.Windows.Forms.DockStyle)(resources.GetObject("btnOK.Dock")));
			this.btnOK.Enabled = ((bool)(resources.GetObject("btnOK.Enabled")));
			this.btnOK.FlatStyle = ((System.Windows.Forms.FlatStyle)(resources.GetObject("btnOK.FlatStyle")));
			this.btnOK.Font = ((System.Drawing.Font)(resources.GetObject("btnOK.Font")));
			this.btnOK.Image = ((System.Drawing.Image)(resources.GetObject("btnOK.Image")));
			this.btnOK.ImageAlign = ((System.Drawing.ContentAlignment)(resources.GetObject("btnOK.ImageAlign")));
			this.btnOK.ImageIndex = ((int)(resources.GetObject("btnOK.ImageIndex")));
			this.btnOK.ImeMode = ((System.Windows.Forms.ImeMode)(resources.GetObject("btnOK.ImeMode")));
			this.btnOK.Location = ((System.Drawing.Point)(resources.GetObject("btnOK.Location")));
			this.btnOK.Name = "btnOK";
			this.btnOK.RightToLeft = ((System.Windows.Forms.RightToLeft)(resources.GetObject("btnOK.RightToLeft")));
			this.btnOK.Size = ((System.Drawing.Size)(resources.GetObject("btnOK.Size")));
			this.btnOK.TabIndex = ((int)(resources.GetObject("btnOK.TabIndex")));
			this.btnOK.Text = resources.GetString("btnOK.Text");
			this.btnOK.TextAlign = ((System.Drawing.ContentAlignment)(resources.GetObject("btnOK.TextAlign")));
			this.btnOK.Visible = ((bool)(resources.GetObject("btnOK.Visible")));
			// 
			// btnCancel
			// 
			this.btnCancel.AccessibleDescription = ((string)(resources.GetObject("btnCancel.AccessibleDescription")));
			this.btnCancel.AccessibleName = ((string)(resources.GetObject("btnCancel.AccessibleName")));
			this.btnCancel.Anchor = ((System.Windows.Forms.AnchorStyles)(resources.GetObject("btnCancel.Anchor")));
			this.btnCancel.BackgroundImage = ((System.Drawing.Image)(resources.GetObject("btnCancel.BackgroundImage")));
			this.btnCancel.DialogResult = System.Windows.Forms.DialogResult.Cancel;
			this.btnCancel.Dock = ((System.Windows.Forms.DockStyle)(resources.GetObject("btnCancel.Dock")));
			this.btnCancel.Enabled = ((bool)(resources.GetObject("btnCancel.Enabled")));
			this.btnCancel.FlatStyle = ((System.Windows.Forms.FlatStyle)(resources.GetObject("btnCancel.FlatStyle")));
			this.btnCancel.Font = ((System.Drawing.Font)(resources.GetObject("btnCancel.Font")));
			this.btnCancel.Image = ((System.Drawing.Image)(resources.GetObject("btnCancel.Image")));
			this.btnCancel.ImageAlign = ((System.Drawing.ContentAlignment)(resources.GetObject("btnCancel.ImageAlign")));
			this.btnCancel.ImageIndex = ((int)(resources.GetObject("btnCancel.ImageIndex")));
			this.btnCancel.ImeMode = ((System.Windows.Forms.ImeMode)(resources.GetObject("btnCancel.ImeMode")));
			this.btnCancel.Location = ((System.Drawing.Point)(resources.GetObject("btnCancel.Location")));
			this.btnCancel.Name = "btnCancel";
			this.btnCancel.RightToLeft = ((System.Windows.Forms.RightToLeft)(resources.GetObject("btnCancel.RightToLeft")));
			this.btnCancel.Size = ((System.Drawing.Size)(resources.GetObject("btnCancel.Size")));
			this.btnCancel.TabIndex = ((int)(resources.GetObject("btnCancel.TabIndex")));
			this.btnCancel.Text = resources.GetString("btnCancel.Text");
			this.btnCancel.TextAlign = ((System.Drawing.ContentAlignment)(resources.GetObject("btnCancel.TextAlign")));
			this.btnCancel.Visible = ((bool)(resources.GetObject("btnCancel.Visible")));
			// 
			// lstArgs
			// 
			this.lstArgs.AccessibleDescription = ((string)(resources.GetObject("lstArgs.AccessibleDescription")));
			this.lstArgs.AccessibleName = ((string)(resources.GetObject("lstArgs.AccessibleName")));
			this.lstArgs.Anchor = ((System.Windows.Forms.AnchorStyles)(resources.GetObject("lstArgs.Anchor")));
			this.lstArgs.BackgroundImage = ((System.Drawing.Image)(resources.GetObject("lstArgs.BackgroundImage")));
			this.lstArgs.ColumnWidth = ((int)(resources.GetObject("lstArgs.ColumnWidth")));
			this.lstArgs.Dock = ((System.Windows.Forms.DockStyle)(resources.GetObject("lstArgs.Dock")));
			this.lstArgs.Enabled = ((bool)(resources.GetObject("lstArgs.Enabled")));
			this.lstArgs.Font = ((System.Drawing.Font)(resources.GetObject("lstArgs.Font")));
			this.lstArgs.HorizontalExtent = ((int)(resources.GetObject("lstArgs.HorizontalExtent")));
			this.lstArgs.HorizontalScrollbar = ((bool)(resources.GetObject("lstArgs.HorizontalScrollbar")));
			this.lstArgs.ImeMode = ((System.Windows.Forms.ImeMode)(resources.GetObject("lstArgs.ImeMode")));
			this.lstArgs.IntegralHeight = ((bool)(resources.GetObject("lstArgs.IntegralHeight")));
			this.lstArgs.ItemHeight = ((int)(resources.GetObject("lstArgs.ItemHeight")));
			this.lstArgs.Location = ((System.Drawing.Point)(resources.GetObject("lstArgs.Location")));
			this.lstArgs.Name = "lstArgs";
			this.lstArgs.RightToLeft = ((System.Windows.Forms.RightToLeft)(resources.GetObject("lstArgs.RightToLeft")));
			this.lstArgs.ScrollAlwaysVisible = ((bool)(resources.GetObject("lstArgs.ScrollAlwaysVisible")));
			this.lstArgs.Size = ((System.Drawing.Size)(resources.GetObject("lstArgs.Size")));
			this.lstArgs.TabIndex = ((int)(resources.GetObject("lstArgs.TabIndex")));
			this.lstArgs.Visible = ((bool)(resources.GetObject("lstArgs.Visible")));
			this.lstArgs.KeyDown += new System.Windows.Forms.KeyEventHandler(this.lstArgs_KeyDown);
			// 
			// btnArgUp
			// 
			this.btnArgUp.AccessibleDescription = ((string)(resources.GetObject("btnArgUp.AccessibleDescription")));
			this.btnArgUp.AccessibleName = ((string)(resources.GetObject("btnArgUp.AccessibleName")));
			this.btnArgUp.Anchor = ((System.Windows.Forms.AnchorStyles)(resources.GetObject("btnArgUp.Anchor")));
			this.btnArgUp.BackgroundImage = ((System.Drawing.Image)(resources.GetObject("btnArgUp.BackgroundImage")));
			this.btnArgUp.Dock = ((System.Windows.Forms.DockStyle)(resources.GetObject("btnArgUp.Dock")));
			this.btnArgUp.Enabled = ((bool)(resources.GetObject("btnArgUp.Enabled")));
			this.btnArgUp.FlatStyle = ((System.Windows.Forms.FlatStyle)(resources.GetObject("btnArgUp.FlatStyle")));
			this.btnArgUp.Font = ((System.Drawing.Font)(resources.GetObject("btnArgUp.Font")));
			this.btnArgUp.Image = ((System.Drawing.Image)(resources.GetObject("btnArgUp.Image")));
			this.btnArgUp.ImageAlign = ((System.Drawing.ContentAlignment)(resources.GetObject("btnArgUp.ImageAlign")));
			this.btnArgUp.ImageIndex = ((int)(resources.GetObject("btnArgUp.ImageIndex")));
			this.btnArgUp.ImeMode = ((System.Windows.Forms.ImeMode)(resources.GetObject("btnArgUp.ImeMode")));
			this.btnArgUp.Location = ((System.Drawing.Point)(resources.GetObject("btnArgUp.Location")));
			this.btnArgUp.Name = "btnArgUp";
			this.btnArgUp.RightToLeft = ((System.Windows.Forms.RightToLeft)(resources.GetObject("btnArgUp.RightToLeft")));
			this.btnArgUp.Size = ((System.Drawing.Size)(resources.GetObject("btnArgUp.Size")));
			this.btnArgUp.TabIndex = ((int)(resources.GetObject("btnArgUp.TabIndex")));
			this.btnArgUp.Text = resources.GetString("btnArgUp.Text");
			this.btnArgUp.TextAlign = ((System.Drawing.ContentAlignment)(resources.GetObject("btnArgUp.TextAlign")));
			this.btnArgUp.Visible = ((bool)(resources.GetObject("btnArgUp.Visible")));
			this.btnArgUp.Click += new System.EventHandler(this.btnArgUp_Click);
			// 
			// btnArgDown
			// 
			this.btnArgDown.AccessibleDescription = ((string)(resources.GetObject("btnArgDown.AccessibleDescription")));
			this.btnArgDown.AccessibleName = ((string)(resources.GetObject("btnArgDown.AccessibleName")));
			this.btnArgDown.Anchor = ((System.Windows.Forms.AnchorStyles)(resources.GetObject("btnArgDown.Anchor")));
			this.btnArgDown.BackgroundImage = ((System.Drawing.Image)(resources.GetObject("btnArgDown.BackgroundImage")));
			this.btnArgDown.Dock = ((System.Windows.Forms.DockStyle)(resources.GetObject("btnArgDown.Dock")));
			this.btnArgDown.Enabled = ((bool)(resources.GetObject("btnArgDown.Enabled")));
			this.btnArgDown.FlatStyle = ((System.Windows.Forms.FlatStyle)(resources.GetObject("btnArgDown.FlatStyle")));
			this.btnArgDown.Font = ((System.Drawing.Font)(resources.GetObject("btnArgDown.Font")));
			this.btnArgDown.Image = ((System.Drawing.Image)(resources.GetObject("btnArgDown.Image")));
			this.btnArgDown.ImageAlign = ((System.Drawing.ContentAlignment)(resources.GetObject("btnArgDown.ImageAlign")));
			this.btnArgDown.ImageIndex = ((int)(resources.GetObject("btnArgDown.ImageIndex")));
			this.btnArgDown.ImeMode = ((System.Windows.Forms.ImeMode)(resources.GetObject("btnArgDown.ImeMode")));
			this.btnArgDown.Location = ((System.Drawing.Point)(resources.GetObject("btnArgDown.Location")));
			this.btnArgDown.Name = "btnArgDown";
			this.btnArgDown.RightToLeft = ((System.Windows.Forms.RightToLeft)(resources.GetObject("btnArgDown.RightToLeft")));
			this.btnArgDown.Size = ((System.Drawing.Size)(resources.GetObject("btnArgDown.Size")));
			this.btnArgDown.TabIndex = ((int)(resources.GetObject("btnArgDown.TabIndex")));
			this.btnArgDown.Text = resources.GetString("btnArgDown.Text");
			this.btnArgDown.TextAlign = ((System.Drawing.ContentAlignment)(resources.GetObject("btnArgDown.TextAlign")));
			this.btnArgDown.Visible = ((bool)(resources.GetObject("btnArgDown.Visible")));
			this.btnArgDown.Click += new System.EventHandler(this.btnArgDown_Click);
			// 
			// lblArgs
			// 
			this.lblArgs.AccessibleDescription = ((string)(resources.GetObject("lblArgs.AccessibleDescription")));
			this.lblArgs.AccessibleName = ((string)(resources.GetObject("lblArgs.AccessibleName")));
			this.lblArgs.Anchor = ((System.Windows.Forms.AnchorStyles)(resources.GetObject("lblArgs.Anchor")));
			this.lblArgs.AutoSize = ((bool)(resources.GetObject("lblArgs.AutoSize")));
			this.lblArgs.Dock = ((System.Windows.Forms.DockStyle)(resources.GetObject("lblArgs.Dock")));
			this.lblArgs.Enabled = ((bool)(resources.GetObject("lblArgs.Enabled")));
			this.lblArgs.Font = ((System.Drawing.Font)(resources.GetObject("lblArgs.Font")));
			this.lblArgs.Image = ((System.Drawing.Image)(resources.GetObject("lblArgs.Image")));
			this.lblArgs.ImageAlign = ((System.Drawing.ContentAlignment)(resources.GetObject("lblArgs.ImageAlign")));
			this.lblArgs.ImageIndex = ((int)(resources.GetObject("lblArgs.ImageIndex")));
			this.lblArgs.ImeMode = ((System.Windows.Forms.ImeMode)(resources.GetObject("lblArgs.ImeMode")));
			this.lblArgs.Location = ((System.Drawing.Point)(resources.GetObject("lblArgs.Location")));
			this.lblArgs.Name = "lblArgs";
			this.lblArgs.RightToLeft = ((System.Windows.Forms.RightToLeft)(resources.GetObject("lblArgs.RightToLeft")));
			this.lblArgs.Size = ((System.Drawing.Size)(resources.GetObject("lblArgs.Size")));
			this.lblArgs.TabIndex = ((int)(resources.GetObject("lblArgs.TabIndex")));
			this.lblArgs.Text = resources.GetString("lblArgs.Text");
			this.lblArgs.TextAlign = ((System.Drawing.ContentAlignment)(resources.GetObject("lblArgs.TextAlign")));
			this.lblArgs.Visible = ((bool)(resources.GetObject("lblArgs.Visible")));
			// 
			// MethodExecuteForm
			// 
			this.AcceptButton = this.btnOK;
			this.AccessibleDescription = ((string)(resources.GetObject("$this.AccessibleDescription")));
			this.AccessibleName = ((string)(resources.GetObject("$this.AccessibleName")));
			this.Anchor = ((System.Windows.Forms.AnchorStyles)(resources.GetObject("$this.Anchor")));
			this.AutoScaleBaseSize = ((System.Drawing.Size)(resources.GetObject("$this.AutoScaleBaseSize")));
			this.AutoScroll = ((bool)(resources.GetObject("$this.AutoScroll")));
			this.AutoScrollMargin = ((System.Drawing.Size)(resources.GetObject("$this.AutoScrollMargin")));
			this.AutoScrollMinSize = ((System.Drawing.Size)(resources.GetObject("$this.AutoScrollMinSize")));
			this.BackgroundImage = ((System.Drawing.Image)(resources.GetObject("$this.BackgroundImage")));
			this.CancelButton = this.btnCancel;
			this.ClientSize = ((System.Drawing.Size)(resources.GetObject("$this.ClientSize")));
			this.Controls.AddRange(new System.Windows.Forms.Control[] {
																		  this.lblArgs,
																		  this.btnArgDown,
																		  this.btnArgUp,
																		  this.lstArgs,
																		  this.btnCancel,
																		  this.btnOK});
			this.Dock = ((System.Windows.Forms.DockStyle)(resources.GetObject("$this.Dock")));
			this.Enabled = ((bool)(resources.GetObject("$this.Enabled")));
			this.Font = ((System.Drawing.Font)(resources.GetObject("$this.Font")));
			this.FormBorderStyle = System.Windows.Forms.FormBorderStyle.FixedDialog;
			this.Icon = ((System.Drawing.Icon)(resources.GetObject("$this.Icon")));
			this.ImeMode = ((System.Windows.Forms.ImeMode)(resources.GetObject("$this.ImeMode")));
			this.Location = ((System.Drawing.Point)(resources.GetObject("$this.Location")));
			this.MaximizeBox = false;
			this.MaximumSize = ((System.Drawing.Size)(resources.GetObject("$this.MaximumSize")));
			this.MinimizeBox = false;
			this.MinimumSize = ((System.Drawing.Size)(resources.GetObject("$this.MinimumSize")));
			this.Name = "MethodExecuteForm";
			this.RightToLeft = ((System.Windows.Forms.RightToLeft)(resources.GetObject("$this.RightToLeft")));
			this.ShowInTaskbar = false;
			this.SizeGripStyle = System.Windows.Forms.SizeGripStyle.Hide;
			this.StartPosition = ((System.Windows.Forms.FormStartPosition)(resources.GetObject("$this.StartPosition")));
			this.Text = resources.GetString("$this.Text");
			this.Visible = ((bool)(resources.GetObject("$this.Visible")));
			this.ResumeLayout(false);

		}
		#endregion


		private void MoveParamDown()
		{
			if (lstArgs.Items.Count == 0 || 
				lstArgs.SelectedIndex == lstArgs.Items.Count - 1)
				return;

			int idx = lstArgs.SelectedIndex;
			object sel = lstArgs.SelectedItem;

			lstArgs.Items.RemoveAt(idx);
			lstArgs.Items.Insert(idx + 1, sel);
			lstArgs.SelectedIndex = idx + 1;
			lstArgs.Focus();
		}

		private void MoveParamUp()
		{
			if (lstArgs.Items.Count == 0 || 
				lstArgs.SelectedIndex == 0)
				return;

			int idx = lstArgs.SelectedIndex;
			object sel = lstArgs.SelectedItem;

			lstArgs.Items.RemoveAt(idx);
			lstArgs.Items.Insert(idx - 1, sel);
			lstArgs.SelectedIndex = idx - 1;
			lstArgs.Focus();
		}

		private void lstArgs_KeyDown(object sender, System.Windows.Forms.KeyEventArgs e)
		{
			e.Handled = true;

			switch (e.KeyCode)
			{
				case Keys.Up:
					MoveParamUp();
					break;

				case Keys.Down:
					MoveParamDown();
					break;

				default:
					e.Handled = false;
					break;
			}
		}

		private void btnArgUp_Click(object sender, System.EventArgs e)
		{
			MoveParamUp();
		}

		private void btnArgDown_Click(object sender, System.EventArgs e)
		{
			MoveParamDown();
		}
	}
}
