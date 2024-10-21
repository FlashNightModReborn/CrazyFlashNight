using System;

namespace FlashSocketServer.Communication
{
	/// <summary>
	/// Summary description for SocketPacket.
	/// </summary>
	public class SocketPacket
	{
		public System.Net.Sockets.Socket Socket;
		public byte[] DataBuffer = new byte[1];
	}
}
