using System;
using System.Net;
using System.Net.Sockets;
using System.Xml;

namespace FlashSocketServer.Communication
{
	/// <summary>
	/// A socket that sends and recieves data to and from Flash.
	/// </summary>
	public class FlashSocket
	{
		private const int DEFAULT_BACKLOG = 10;

		#region Member Variables

		private int m_portnumber;
		private int m_backlog = DEFAULT_BACKLOG;
		private Socket m_socketlistener;
		private Socket m_socketclient = null;
		private AsyncCallback m_datareciever;
		private bool m_socketalive = false;
		private string m_currentmessage = "";
		private System.Collections.Queue m_queuedSends;

		#endregion

		#region Constructors

		/// <summary>
		/// Creates a new instance of FlashSocket.
		/// </summary>
		public FlashSocket()
		{
			m_socketlistener = null;
			m_queuedSends = new System.Collections.Queue();
			m_datareciever = new AsyncCallback(OnDataReceived);
		}


		/// <summary>
		/// Creates a new instance of FlashSocket and creates the socket
		/// listening on portNumber.
		/// </summary>
		/// <param name="portNumber">
		/// The port to listen on.
		/// </param>
		public FlashSocket(int portNumber) 
			: this(portNumber, DEFAULT_BACKLOG)
		{ }


		/// <summary>
		/// Creates a new instance of FlashSocket and creates the socket
		/// listening on portNumber with a maximum backlog queue length
		/// or backLog.
		/// </summary>
		/// <param name="portNumber">
		/// The port to listen on.
		/// </param>
		/// <param name="backLog">
		/// The socket's maximum number of pending connection requests.
		/// </param>
		public FlashSocket(int portNumber, int backLog) : this()
		{
			m_portnumber = portNumber;
			m_backlog = backLog;
			CreateSocket();
		}
		
		#endregion

		#region Properties

		/// <summary>
		/// Gets / sets whether the socket is alive.
		/// </summary>
		public bool IsAlive
		{
			get
			{
				return m_socketalive;
			}
			set
			{
				if (m_socketalive == value)
					return;

				m_socketalive = value;

				if (value)
					CreateSocket();
				else
					KillSocket();
			}
		}


		/// <summary>
		/// Gets / sets the port number on which the socket exists.
		/// </summary>
		/// <remarks>
		/// This property can only be set while IsAlive is false.
		/// </remarks>
		public int Port
		{
			get
			{
				return m_portnumber;
			}
			set
			{
				if (m_socketalive)
				{
					throw new InvalidOperationException(
						"Port can only be set after setting IsAlive to false or calling KillSocket()");
				}

				m_portnumber = value;
			}
		}


		/// <summary>
		/// Gets the socket's maximum number of pending connection requests.
		/// </summary>
		public int BackLog
		{
			get
			{
				return m_backlog;
			}
		}

		#endregion

		#region Internal Event Handlers, Events (and their delegates)

		public delegate void ClientConnectHandler(Socket socket);

		/// <summary>
		/// Occurs when the client connects.
		/// </summary>
		public event ClientConnectHandler ClientConnect;

		/// <summary>
		/// Occurs when the client disconnects.
		/// </summary>
		public event EventHandler ClientDisconnect;

		/// <summary>
		/// Fired when a connection to a Flash movie is made.
		/// </summary>
		/// <param name="target"></param>
		protected void OnClientConnect(IAsyncResult target)
		{
			try
			{
				//
				// Ends the connection acceptance.
				//
				m_socketclient = m_socketlistener.EndAccept(target);

				//
				// Mark connection as alive.
				//
				m_socketalive = true;

				//
				// Dispatch event.
				//
				if (ClientConnect != null)
					ClientConnect(m_socketclient);

				//
				// Send the messages waiting in the qeueue.
				//
				SendQueuedMessages();

				//
				// Wait for the client to send data.
				//
				WaitForData(m_socketclient);
			}
			catch(ObjectDisposedException)
			{
				KillSocket();

				if (ClientDisconnect != null)
					ClientDisconnect(this, EventArgs.Empty);
			}
			catch(SocketException e)
			{
				System.Diagnostics.Debugger.Log(0, "1", "\n" + e.ToString() + "\n");
			}
		}

		public delegate void DataRecievedHandler(Socket socket, XmlNode data);
		public event DataRecievedHandler DataRecieved;

		/// <summary>
		/// Fired when data is recieved from the socket.
		/// </summary>
		/// <param name="asyn"></param>
		protected void OnDataReceived(IAsyncResult asyn)
		{
			try
			{	
				//
				// Get the socket packet (as set by BeginRecieve's state)
				//
				SocketPacket spacket = (SocketPacket)asyn.AsyncState ;
				
				//
				// Decode the text.
				//
				int numbytes = 0;
				numbytes = spacket.Socket.EndReceive(asyn);
				char[] chars = new char[numbytes];
				System.Text.Decoder d = System.Text.Encoding.UTF8.GetDecoder();
				int charLen = d.GetChars(spacket.DataBuffer, 0, numbytes, chars, 0);
				string recievedData = new String(chars);

				m_currentmessage += recievedData;

				//
				// Dispatch event.
				//
				if (recievedData == "\0" && DataRecieved != null)
				{
					XmlNode node;

					try
					{
						XmlDocument doc = new XmlDocument();
						doc.LoadXml(m_currentmessage);
						node = doc.FirstChild;
					}
					catch
					{
						m_currentmessage = "";
						WaitForData(m_socketclient);
						return;
					}

					DataRecieved(spacket.Socket, node);
					m_currentmessage = "";
				}

				//
				// Wait for data again.
				//
				WaitForData(m_socketclient);
			}
			catch (ObjectDisposedException )
			{
				KillSocket();

				if (ClientDisconnect != null)
					ClientDisconnect(this, EventArgs.Empty);
			}
			catch(SocketException e)
			{
				System.Diagnostics.Debugger.Log(0,"1","\n" + e.ToString() + "\n");
			}
		}

		#endregion

		#region Public Methods

		/// <summary>
		/// Creates the socket.
		/// </summary>
		public void CreateSocket()
		{
			try
			{
				if (m_socketlistener == null)
				{
					//
					// Create the socket.
					//
					m_socketlistener = new Socket(AddressFamily.InterNetwork,
						SocketType.Stream, ProtocolType.Tcp);

					//
					// Create the endpoint.
					//
					IPEndPoint ep = new IPEndPoint(IPAddress.Any, m_portnumber);

					//
					// Bind the socket to the server's ip / port.
					//
					m_socketlistener.Bind(ep);
				}

				//
				// Tell the socket to begin listening.
				//
				m_socketlistener.Listen(m_backlog);
				
				//
				// Begin listening
				//
				m_socketlistener.BeginAccept(new AsyncCallback(OnClientConnect), null);
			}
			catch (SocketException e)
			{
				KillSocket();

				if (ClientDisconnect != null)
					ClientDisconnect(this, EventArgs.Empty);
			}
		}


		/// <summary>
		/// Kills the socket connection.
		/// </summary>
		public void KillSocket()
		{						
			if (m_socketlistener.Connected)
			{
				m_socketlistener.Shutdown(SocketShutdown.Both);
				m_socketlistener.Close();
			}
						
			if (m_socketclient.Connected)
			{
				m_socketclient.Shutdown(SocketShutdown.Both);
				m_socketclient.Close();
			}

			m_socketalive = false;
		}


		/// <summary>
		/// Sends data to the Flash client.
		/// </summary>
		/// <param name="data"></param>
		public void Send(SendableData data)
		{
			if (m_socketclient == null)
			{
				m_queuedSends.Enqueue(data);
				return;
			}

			byte[] byData = System.Text.Encoding.ASCII.GetBytes(data.Xml + "\0");

			try
			{
				m_socketclient.Send(byData);
			}
			catch 
			{
				if (!m_socketclient.Connected)
				{
					this.KillSocket();
					
					if (ClientDisconnect != null)
						ClientDisconnect(this, EventArgs.Empty);
				}
			}
		}

		#endregion

		#region Private Methods

		/// <summary>
		/// Waits for data to arrive from the socket connection.
		/// </summary>
		/// <param name="s">The socket to wait on.</param>
		private void WaitForData(Socket s)
		{
			try
			{
				SocketPacket spacket = new SocketPacket();
				spacket.Socket = s;

				//
				// Begin listening for data.
				//
				s.BeginReceive(spacket.DataBuffer, 0, spacket.DataBuffer.Length,
					SocketFlags.None, m_datareciever, spacket);
			}
			catch (SocketException e)
			{
				
			}
		}

		private void SendQueuedMessages()
		{
			SendableData data;
			//while (null != (data = (SendableData) m_queuedSends.Dequeue()))
			//	Send(data);
		}

		#endregion

	}
}
