using System;
using System.Collections;
using System.ComponentModel;
using System.Drawing;
using System.Data;
using System.Windows.Forms;

using SourceGrid2.Cells.Real;

using FlashSocketServer.Communication;
using FlashSocketServer.Explore;

namespace FlashSocketServer
{
	/// <summary>
	/// Summary description for PropertyInspectorForm.
	/// </summary>
	public class PropertyInspectorForm : System.Windows.Forms.UserControl
	{
		private FlashObject m_selectedObject;
		private int m_grid_delta_x;
		private int m_grid_delta_y;
		private int m_list_delta_y;

		private ObjectManager m_objmanager;
		private System.Windows.Forms.TextBox txtObjectPath;
		private System.Windows.Forms.Label lblObjectPath;
		private SourceGrid2.Grid gridProperties;
		private System.Windows.Forms.ListBox lstRecentObjects;
		private System.Windows.Forms.Button btnInspect;
		private System.Windows.Forms.TreeView treeObjects;
		private System.Windows.Forms.CheckBox btnRecent;
		private System.Windows.Forms.Label lblCurrentObject;
		private System.Windows.Forms.Label lblCurrentObjectValue;
		/// <summary> 
		/// Required designer variable.
		/// </summary>
		private System.ComponentModel.Container components = null;

		public PropertyInspectorForm(FlashSocket socket)
		{
			// This call is required by the Windows.Forms Form Designer.
			InitializeComponent();

			m_objmanager = new ObjectManager(socket, this);

			m_selectedObject = null;

			//
			// Add root tree nodes
			//
			treeObjects.Nodes.Add(m_objmanager.Root.TreeNode);
			treeObjects.Nodes.Add(m_objmanager.Global.TreeNode);

			//
			// Layout stuff
			//
			m_grid_delta_x = this.Width - gridProperties.Width;
			m_grid_delta_y = this.Height - gridProperties.Height;
			m_list_delta_y = this.Height - treeObjects.Height;

			SetupGrid();
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

		#region Component Designer generated code
		/// <summary> 
		/// Required method for Designer support - do not modify 
		/// the contents of this method with the code editor.
		/// </summary>
		private void InitializeComponent()
		{
			this.btnInspect = new System.Windows.Forms.Button();
			this.txtObjectPath = new System.Windows.Forms.TextBox();
			this.lblObjectPath = new System.Windows.Forms.Label();
			this.gridProperties = new SourceGrid2.Grid();
			this.lstRecentObjects = new System.Windows.Forms.ListBox();
			this.treeObjects = new System.Windows.Forms.TreeView();
			this.btnRecent = new System.Windows.Forms.CheckBox();
			this.lblCurrentObject = new System.Windows.Forms.Label();
			this.lblCurrentObjectValue = new System.Windows.Forms.Label();
			this.SuspendLayout();
			// 
			// btnInspect
			// 
			this.btnInspect.Enabled = false;
			this.btnInspect.Location = new System.Drawing.Point(8, 64);
			this.btnInspect.Name = "btnInspect";
			this.btnInspect.TabIndex = 2;
			this.btnInspect.Text = "&Inspect";
			this.btnInspect.Click += new System.EventHandler(this.btnInspect_Click);
			// 
			// txtObjectPath
			// 
			this.txtObjectPath.Location = new System.Drawing.Point(8, 32);
			this.txtObjectPath.Name = "txtObjectPath";
			this.txtObjectPath.Size = new System.Drawing.Size(272, 20);
			this.txtObjectPath.TabIndex = 1;
			this.txtObjectPath.Text = "";
			this.txtObjectPath.TextChanged += new System.EventHandler(this.txtObjectPath_TextChanged);
			// 
			// lblObjectPath
			// 
			this.lblObjectPath.Location = new System.Drawing.Point(8, 8);
			this.lblObjectPath.Name = "lblObjectPath";
			this.lblObjectPath.TabIndex = 4;
			this.lblObjectPath.Text = "Object Path:";
			// 
			// gridProperties
			// 
			this.gridProperties.AutoSizeMinHeight = 10;
			this.gridProperties.AutoSizeMinWidth = 10;
			this.gridProperties.AutoStretchColumnsToFitWidth = true;
			this.gridProperties.AutoStretchRowsToFitHeight = false;
			this.gridProperties.BackColor = System.Drawing.SystemColors.ControlLightLight;
			this.gridProperties.BorderStyle = System.Windows.Forms.BorderStyle.Fixed3D;
			this.gridProperties.ContextMenuStyle = SourceGrid2.ContextMenuStyle.None;
			this.gridProperties.CustomSort = false;
			this.gridProperties.GridToolTipActive = true;
			this.gridProperties.Location = new System.Drawing.Point(288, 32);
			this.gridProperties.Name = "gridProperties";
			this.gridProperties.Size = new System.Drawing.Size(336, 292);
			this.gridProperties.SpecialKeys = SourceGrid2.GridSpecialKeys.Default;
			this.gridProperties.TabIndex = 5;
			// 
			// lstRecentObjects
			// 
			this.lstRecentObjects.Location = new System.Drawing.Point(104, 64);
			this.lstRecentObjects.Name = "lstRecentObjects";
			this.lstRecentObjects.Size = new System.Drawing.Size(132, 108);
			this.lstRecentObjects.TabIndex = 6;
			this.lstRecentObjects.Visible = false;
			this.lstRecentObjects.MouseDown += new System.Windows.Forms.MouseEventHandler(this.lstRecentObjects_MouseDown);
			this.lstRecentObjects.SelectedIndexChanged += new System.EventHandler(this.lstRecentObjects_SelectedIndexChanged);
			// 
			// treeObjects
			// 
			this.treeObjects.HideSelection = false;
			this.treeObjects.HotTracking = true;
			this.treeObjects.ImageIndex = -1;
			this.treeObjects.Location = new System.Drawing.Point(8, 100);
			this.treeObjects.Name = "treeObjects";
			this.treeObjects.SelectedImageIndex = -1;
			this.treeObjects.Size = new System.Drawing.Size(272, 224);
			this.treeObjects.TabIndex = 4;
			this.treeObjects.AfterExpand += new System.Windows.Forms.TreeViewEventHandler(this.treeObjects_AfterExpand);
			this.treeObjects.AfterSelect += new System.Windows.Forms.TreeViewEventHandler(this.treeObjects_AfterSelect);
			// 
			// btnRecent
			// 
			this.btnRecent.Appearance = System.Windows.Forms.Appearance.Button;
			this.btnRecent.BackColor = System.Drawing.SystemColors.ControlLight;
			this.btnRecent.Location = new System.Drawing.Point(84, 64);
			this.btnRecent.Name = "btnRecent";
			this.btnRecent.Size = new System.Drawing.Size(20, 24);
			this.btnRecent.TabIndex = 3;
			this.btnRecent.Text = ">";
			this.btnRecent.Leave += new System.EventHandler(this.btnRecent_Leave);
			this.btnRecent.CheckedChanged += new System.EventHandler(this.btnRecent_CheckedChanged);
			// 
			// lblCurrentObject
			// 
			this.lblCurrentObject.Location = new System.Drawing.Point(292, 12);
			this.lblCurrentObject.Name = "lblCurrentObject";
			this.lblCurrentObject.Size = new System.Drawing.Size(84, 23);
			this.lblCurrentObject.TabIndex = 10;
			this.lblCurrentObject.Text = "Current Object:";
			// 
			// lblCurrentObjectValue
			// 
			this.lblCurrentObjectValue.Font = new System.Drawing.Font("Microsoft Sans Serif", 8.25F, System.Drawing.FontStyle.Bold, System.Drawing.GraphicsUnit.Point, ((System.Byte)(0)));
			this.lblCurrentObjectValue.Location = new System.Drawing.Point(376, 12);
			this.lblCurrentObjectValue.Name = "lblCurrentObjectValue";
			this.lblCurrentObjectValue.Size = new System.Drawing.Size(244, 23);
			this.lblCurrentObjectValue.TabIndex = 11;
			// 
			// PropertyInspectorForm
			// 
			this.Controls.AddRange(new System.Windows.Forms.Control[] {
																		  this.btnRecent,
																		  this.lstRecentObjects,
																		  this.gridProperties,
																		  this.lblObjectPath,
																		  this.txtObjectPath,
																		  this.btnInspect,
																		  this.treeObjects,
																		  this.lblCurrentObjectValue,
																		  this.lblCurrentObject});
			this.Name = "PropertyInspectorForm";
			this.Size = new System.Drawing.Size(632, 328);
			this.VisibleChanged += new System.EventHandler(this.PropertyInspectorForm_VisibleChanged);
			this.MouseDown += new System.Windows.Forms.MouseEventHandler(this.PropertyInspectorForm_MouseDown);
			this.Layout += new System.Windows.Forms.LayoutEventHandler(this.PropertyInspectorForm_Layout);
			this.ResumeLayout(false);

		}
		#endregion

		#region Private Methods

		/// <summary>
		/// Sets up the grid column headers.
		/// </summary>
		private void SetupGrid()
		{
			SourceGrid2.Grid g = gridProperties;
			g.ColumnsCount = 3;
			g.Selection.SelectionMode = SourceGrid2.GridSelectionMode.Row;
			g.Rows.Insert(0);

			//
			// Create column headers
			//
			SourceGrid2.Cells.Real.ColumnHeader h;
			
			h = new SourceGrid2.Cells.Real.ColumnHeader("Name");
			g[0, 0] = h;

			h = new SourceGrid2.Cells.Real.ColumnHeader("Type");
			g[0, 1] = h;

			h = new SourceGrid2.Cells.Real.ColumnHeader("Value");
			g[0, 2] = h;
		}


		/// <summary>
		/// Clears the contents out of the grid.
		/// </summary>
		private void ClearGridContents()
		{
			if (gridProperties.Rows.Count > 1)
				gridProperties.Rows.RemoveRange(1, gridProperties.Rows.Count - 1);
		}


		/// <summary>
		/// Displays the object's properties in the grid, as well as information
		/// about the object itself.
		/// </summary>
		/// <param name="props"></param>
		private void DisplayObjectProperties(FlashObject obj)
		{
			lblCurrentObjectValue.Text = obj.Path.ToString();
			treeObjects.SelectedNode = obj.TreeNode;

			//
			// Display properties in the grid.
			//
			ClearGridContents(); // clear grid

			FlashObjectCollection props = obj.Properties;

			//
			// Do nothing if no props.
			//
			if (props.Count == 0)
				return;

			SourceGrid2.Grid g = gridProperties;
			g.Rows.InsertRange(1, props.Count);
			
			//
			// Insert the rows.
			//
			SourceGrid2.Cells.Real.Cell c;
			FlashObject current;
			System.Collections.IDictionaryEnumerator itr = props.GetEnumerator();
			int counter = 1;

			while (itr.MoveNext())
			{	
				current = itr.Value as FlashObject;

				//
				// Associate the FlashObject with the row.
				//
				g.Rows[counter].Tag = current;

				//
				// Add the cells.
				//
				c = new SourceGrid2.Cells.Real.Cell(current.InstanceName);
				g[counter, 0] = c;

				c = new SourceGrid2.Cells.Real.Cell(current.Type);
				g[counter, 1] = c;

				//
				// If the FlashObject is of type Object, then display a view button.
				//
				switch (current.Type)
				{
					case FlashObject.ObjectType.Object:
					case FlashObject.ObjectType.MovieClip:
						//
						// Add view link
						//
						c = new SourceGrid2.Cells.Real.Link("View", 
							new SourceGrid2.PositionEventHandler(gridProperties_ViewCellClick));

						break;

					case FlashObject.ObjectType.Function:

						//
						// Add view link
						//
						c = new SourceGrid2.Cells.Real.Link("Execute...", 
							new SourceGrid2.PositionEventHandler(gridProperties_ExecuteCellClick));

						break;

					default:
						//
						// Add standard cell.
						//
						c = new SourceGrid2.Cells.Real.Cell(current.Value);

						break;

				}					

				g[counter, 2] = c;

				counter++;
			}
		}

		#endregion

		#region Event Handlers

		/// <summary>
		/// Lays out the form.
		/// </summary>
		/// <param name="sender"></param>
		/// <param name="e"></param>
		private void PropertyInspectorForm_Layout(object sender, System.Windows.Forms.LayoutEventArgs e)
		{
			this.SuspendLayout();
			
			gridProperties.Width = this.Width - m_grid_delta_x;
			gridProperties.Height = this.Height - m_grid_delta_y;
			treeObjects.Height = this.Height - m_list_delta_y;

			this.ResumeLayout();
		}


		private void lstRecentObjects_SelectedIndexChanged(object sender, System.EventArgs e)
		{
			txtObjectPath.Text = lstRecentObjects.SelectedItem.ToString();
		}


		/// <summary>
		/// Fired when the inspect button is clicked.
		/// 
		/// This will request object data from the client.
		/// </summary>
		/// <param name="sender"></param>
		/// <param name="e"></param>
		private void btnInspect_Click(object sender, System.EventArgs e)
		{
			Cursor.Current = Cursors.WaitCursor;

			string path = txtObjectPath.Text;

			m_objmanager.RequestObjectProperties(path, 
				new ObjectManager.ObjectRecievedHandler(objManager_ObjectRecieved));

			if (!lstRecentObjects.Items.Contains(path))
				lstRecentObjects.Items.Add(path);
		}

		private void gridProperties_ExecuteCellClick(object sender, SourceGrid2.PositionEventArgs args)
		{
			FlashObject obj = gridProperties.Rows[args.Position.Row].Tag as FlashObject;

			MethodExecuteForm execute = new MethodExecuteForm();

			//
			// If OK was pressed, execute the method.
			//
			if (execute.ShowDialog(this) == DialogResult.OK)
			{

			}

			execute.Dispose();
		}

		/// <summary>
		/// Fired when a "View" cell in the property grid is clicked.
		/// 
		/// This will request object data from the client.
		/// </summary>
		/// <param name="sender"></param>
		/// <param name="args"></param>
		private void gridProperties_ViewCellClick(object sender, SourceGrid2.PositionEventArgs args)
		{
			FlashObject obj = gridProperties.Rows[args.Position.Row].Tag as FlashObject;

			//
			// Set the selected object (so that treeObjects_AfterSelect and
			// treeObjects_AfterExpand don't trigger manager calls.
			//
			m_selectedObject = obj;

			//
			// Select and expand the node.
			//
			m_selectedObject.TreeNode.Expand();

			//
			// Set the wait cursor (to block input).
			//
			Cursor.Current = Cursors.WaitCursor;

			//
			// Request the object's properties from the client.
			//
			m_objmanager.RequestObjectProperties(obj.Path, 
				new ObjectManager.ObjectRecievedHandler(objManager_ObjectRecieved));

			string path = obj.Path.ToString();

			//
			// Add it to the recent objects list if it isn't already there.
			//
			if (!lstRecentObjects.Items.Contains(path))
				lstRecentObjects.Items.Add(path);

			treeObjects.SelectedNode = obj.TreeNode;
		}


		/// <summary>
		/// Fired when a previously requested object has been recieved.
		/// </summary>
		/// <param name="obj"></param>
		private void objManager_ObjectRecieved(FlashObject obj)
		{
			treeObjects.Invoke(new ObjectEventHandler(objManager_ObjectRecieved_CT), 
				new object[1] {obj});
		}

		/// <summary>
		/// Fired when a previously requested object has been recieved (and is scoped to
		/// the control thread).
		/// </summary>
		/// <param name="obj"></param>
		private void objManager_ObjectRecieved_CT(object obj)
		{
			DisplayObjectProperties((FlashObject)obj);
			
			Cursor.Current = Cursors.Default;
		}


		/// <summary>
		/// Fired when the text changes in the object path selector.
		/// </summary>
		/// <param name="sender"></param>
		/// <param name="e"></param>
		private void txtObjectPath_TextChanged(object sender, System.EventArgs e)
		{
			btnInspect.Enabled = txtObjectPath.Text.Length > 0;
		}


		/// <summary>
		/// Fired when the visibility of this form changes.
		/// </summary>
		/// <param name="sender"></param>
		/// <param name="e"></param>
		private void PropertyInspectorForm_VisibleChanged(object sender, System.EventArgs e)
		{
			if (!this.Visible)
				return;

			this.FindForm().AcceptButton = btnInspect;
			txtObjectPath.Focus();
		}


		private void btnRecent_CheckedChanged(object sender, System.EventArgs e)
		{
			lstRecentObjects.Visible = btnRecent.Checked;
		}


		private void lstRecentObjects_MouseDown(object sender, System.Windows.Forms.MouseEventArgs e)
		{
			btnRecent.Checked = false;
		}


		private void btnRecent_Leave(object sender, System.EventArgs e)
		{
			if (!lstRecentObjects.Focused)
				btnRecent.Checked = false;
		}

		private void PropertyInspectorForm_MouseDown(object sender, System.Windows.Forms.MouseEventArgs e)
		{
			btnRecent.Checked = false;
		}

		private void treeObjects_AfterSelect(object sender, System.Windows.Forms.TreeViewEventArgs e)
		{
			FlashObject obj = e.Node.Tag as FlashObject;

			if (obj != null && obj != m_selectedObject)
			{
				m_selectedObject = obj;
				DisplayObjectProperties(obj);
			}
		}

		private void treeObjects_AfterExpand(object sender, System.Windows.Forms.TreeViewEventArgs e)
		{
			FlashObject obj = e.Node.Tag as FlashObject;

			if (obj != m_selectedObject || !obj.IsFilled)
			{
				m_selectedObject = obj;
				treeObjects.SelectedNode = obj.TreeNode;
				m_objmanager.RequestObjectProperties(obj.Path, 
					new ObjectManager.ObjectRecievedHandler(objManager_ObjectRecieved));
			}
		}

		#endregion


	}
}
