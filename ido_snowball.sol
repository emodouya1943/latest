
pragma solidity ^0.8.6;

import "./libs/ReentrancyGuard.sol";
import "./libs/Ownable.sol";
import "./libs/SafeMath.sol";
import "./libs/SafeERC20.sol";
import "./libs/IERC20.sol";
import "./libs/TransferHelp.sol";


// SPDX-License-Identifier: Unlicensed

contract IDOSB is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 immutable idoAmount1;
    uint256 immutable idoAmount2;
    uint256 immutable idoAmount3;
    uint256 immutable initIDOPrice;
    uint256 public totalIDOAmount; 
    IERC20 paytoken;
    IERC20 _snowToken;
    address[] private idoUsers;
    address public _destroyAddress;
    bool public idoFinished = false;

    address[] private _blocked;  //black list

    mapping(address => bool) private _isBlocked;
    mapping(address => address) public inviterMe;  
    mapping(address => address[]) public meInvited; 

    struct OrderInfo {
		uint256 payAmount;  
		uint256 idoTime; 
        uint256 totalReleaseAmount; 
		uint256 releasedAmount;  
		uint256 lastReleaseTime; 
        uint256 invitRewards; 
        uint256 realtimeAch;
        uint256 myAch;  
        uint256 lastCalcTotalAch;
		uint256 lastCalcSmallAch;
        address lastCalcBigAddress;
    }

    mapping (address=>OrderInfo)  userOrder;

    event IDOJoined(address indexed user,address inviter, uint256 amount, uint256 totalreleaseamount);
    event SnowTokenReleased(address indexed user, address calcbigaddress, uint256 releaseamount, uint256 calcsmallach, uint256 calctotalach);

    function getIdoUsers() external view returns(address[] memory) {
        return idoUsers;
    }


    function getMyIdoOrder() external view returns(OrderInfo memory) {
        address from = _msgSender();
        OrderInfo memory b = userOrder[from];

        return b;
    }


    function getUsrIdoOrder(address account) external view returns(OrderInfo memory) {
        address from = account;
        OrderInfo memory b = userOrder[from];

        return b;
    }


    function isUsrIdoOrderFinished(address account) public view returns(bool) {
        bool isok = false;
        address from = account;
        OrderInfo memory b = userOrder[from];
        if (b.totalReleaseAmount>0 && b.totalReleaseAmount==b.releasedAmount){
            isok = true;
        }

        return isok;
    }

    function getMyAch(address account) public view returns(uint256){
        return userOrder[account].myAch;
    }

    function getUserAch(address account) public view returns(uint256 totalAch,uint256 bigAch, address bigAddr) {
        require(account != address(0) && !isContract(account), "account from the zero or contract address");

        uint256 _ttAch = 0;
        uint256 _bigAch = 0;
        address curinvited;
        address _bigAddr;
        if (meInvited[account].length>0){
            for (uint j=0;j<meInvited[account].length;j++){
                curinvited = meInvited[account][j];
                OrderInfo memory b = userOrder[curinvited];
                _ttAch = _ttAch.add(b.realtimeAch);
                if (b.realtimeAch>_bigAch){
                    _bigAch = b.realtimeAch;
                    _bigAddr = curinvited;
                }
            }
        }

        return (_ttAch,_bigAch,_bigAddr);
    }

    function getInviter() public view returns (address) {
        address account = _msgSender();
        return inviterMe[account];
    }

    function getInvitedAddress() public view returns (address[] memory) {
        address account = _msgSender();
        return meInvited[account];
    }

    function getInvitedAddressOrders() public view returns (address[] memory _meinvited,OrderInfo[] memory _orders) {
        address account = _msgSender();
        
        _meinvited = meInvited[account];
        if (_meinvited.length>0){
            _orders = new OrderInfo[](_meinvited.length);
            for (uint256 i=0;i<_meinvited.length;i++){
                _orders[i] = userOrder[_meinvited[i]];
            }
        }
        return (_meinvited,_orders);
    }


    function getAnyInviter(address account) public view returns (address) {
        return inviterMe[account];
    }

    function getAnyInvitedAddress(address account) public view returns (address[] memory) {
        return meInvited[account];
    }

    function isBlocked(address account) public view returns (bool) {
        return _isBlocked[account];
    }    


    receive() external payable {}

    function isContract(address account) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    function claimTokens() public onlyOwner {
        payable(_owner).transfer(address(this).balance);
    }

    function claimOtherTokens(address token,address to, uint256 amount) public onlyOwner returns(bool sent){
        require(to != address(this) && to != address(0), "Error target address");
        uint256 _contractBalance = IERC20(token).balanceOf(address(this));
        if (token == address(this)){
            require(amount<_contractBalance ,"Can't let you take all native token");
        }
        if (amount>0 && amount <= _contractBalance){
            sent = IERC20(token).transfer(to, amount);
        }else{
            return false;
        }
    }

    function approveForTokens(address token,address spender, uint256 amount) public onlyOwner {
        require(token != address(0) && spender != address(0), "Error token or spender address");
        require(token != address(this) && amount>0, "Can't take native token or error approve amount");
        IERC20(token).approve(spender, amount);
    }

    function getBlocked() public view onlyOwner returns (address[] memory) {
        return _blocked;
    }

    function setBlocked(address account,bool isBlock) public onlyOwner returns(bool){
        require(account != _owner && account != address(0),"Can't set owner or zero");
        bool isok = false;
        bool _isblock = isBlock;
        if (_isblock){
            require(!_isBlocked[account], "Address already blocked!");
            isok = true;
            _isBlocked[account] = true;
            _blocked.push(account);

        }else{
            require(_isBlocked[account], "Address not blocked!");
            
            for (uint256 i = 0; i < _blocked.length; i++) {
                if (_blocked[i] == account) {
                    isok = true;
                    _blocked[i] = _blocked[_blocked.length - 1];
                    _isBlocked[account] = false;
                    _blocked.pop();
                    break;
                }
            }
        }
        return isok;
    }

    function setIdoFinished(bool _isFinished) public onlyOwner {
        idoFinished = _isFinished;
    }

    function setSnowToken(IERC20 _snowtoken) public onlyOwner {
        require(address(_snowtoken) != address(0) && isContract(address(_snowtoken)), "Error SnowToken address");
        _snowToken = _snowtoken;
    }
    
    function autoSetInviter(address account, address newinviter) external returns(bool){
        bool isok = false;
        bool _needsetinviter = true;
        address from = _msgSender();
        require(from == address(_snowToken) && address(_snowToken) !=address(0), "Snowtoken error or not seted");
        
        if (_isBlocked[newinviter] || _isBlocked[account] || inviterMe[account] != address(0)
            || newinviter == address(0) || isContract(newinviter) || isContract(account)){
             _needsetinviter = false;
             return isok;
        }

        address _newinviterups = inviterMe[newinviter];
        if (_newinviterups==address(0) || meInvited[account].length > 0){
             _needsetinviter = false;
             return isok;            
        }
        while (_newinviterups!=address(0)) {
            if (_newinviterups == account){
                // require(_newinviterups != account, "you are higher ups of newinviter");
                _needsetinviter = false;
                _newinviterups = address(0);
                break;
            }else{
                _newinviterups = inviterMe[_newinviterups];
            }
        }
        
        if (meInvited[newinviter].length>0){
            for (uint j=0;j<meInvited[newinviter].length;j++){
                if (meInvited[newinviter][j] == account) {
                    _needsetinviter = false;
                    break;
                }
            }
        }
        
        if (_needsetinviter){
            meInvited[newinviter].push(account); 
            inviterMe[account] = newinviter;
            isok = true;
        }

        return isok;        
    }

    function setInviter(address newinviter) external returns(bool){
        bool isok = false;
        address account = _msgSender();
        require(!_isBlocked[newinviter] && !_isBlocked[account], "your address or inviter address has blocked");
        require(!isContract(account), "account can not be contract address");
        require(newinviter != address(0) && !isContract(newinviter), "new inviter is zero or contract address");
        require(inviterMe[account]== address(0), "address is not newer");
        // require(idoFinished, "IDO has not finished");

        address _newinviterups = inviterMe[newinviter];
        require(_newinviterups!=address(0),"new inviter invaild");
        require(meInvited[account].length==0,"you are not a newer");

        while (_newinviterups!=address(0)) {
            require(_newinviterups != account && !_isBlocked[_newinviterups], "you are higher ups of newinviter or have blocked ups");
            _newinviterups = inviterMe[_newinviterups];
        }
        
        if (meInvited[newinviter].length>0){
            for (uint j=0;j<meInvited[newinviter].length;j++){
                require(meInvited[newinviter][j] != account, "address existed");
            }
        }
        
        meInvited[newinviter].push(account); 
        inviterMe[account] = newinviter;
        
        isok = true;
        return isok;
    }

    function increaseUserAch(address account, uint256 amount) external returns(bool){
        bool isok = false;
        bool _needincrease = true;
        address from = _msgSender();
        uint256 _aRealtimeAch = 0;

        require(from == address(_snowToken) && address(_snowToken) !=address(0), "Snowtoken error or not seted");

        if (account == address(0) || isContract(account) ||_isBlocked[account]){
            _needincrease = false;
        }

        if (_needincrease){
            _aRealtimeAch = userOrder[account].realtimeAch;
            userOrder[account].realtimeAch = _aRealtimeAch.add(amount);
            userOrder[account].myAch = userOrder[account].myAch.add(amount);

            address _newinviterups = inviterMe[account];
            uint256 _levs = 0;
            while (_newinviterups != address(0) && _levs < 24) {
                _levs = _levs.add(1);
                _aRealtimeAch = userOrder[_newinviterups].realtimeAch;
                userOrder[_newinviterups].realtimeAch = _aRealtimeAch.add(amount);
                _releaseSnowToken(_newinviterups);
                _newinviterups = inviterMe[_newinviterups];
            }
            isok = true;
        }

        return isok;
    }
    
    
    function _releaseSnowToken(address account) private {
        uint256 _thisTokenBalance = _snowToken.balanceOf(address(this));

        uint256 _ttAch = 0;
        uint256 _bigAch = 0;
        address _bigAddress;
        
        if (!_isBlocked[account]){
            (_ttAch,_bigAch,_bigAddress) = getUserAch(account); 
            OrderInfo memory _userOrder = userOrder[account];
            // uint256 
            uint256 _restReleaseAmount = _userOrder.totalReleaseAmount.sub(_userOrder.releasedAmount);
            
            if (_restReleaseAmount>0){
                uint256 _curSmallAch = _ttAch.sub(_bigAch);
                if ((_curSmallAch.sub(_userOrder.lastCalcSmallAch)) >= _userOrder.totalReleaseAmount.mul(6).div(10)){
                    _userOrder.lastCalcSmallAch = _userOrder.lastCalcSmallAch.add(_userOrder.totalReleaseAmount.mul(6).div(10));
                    
                    if (_restReleaseAmount>=_userOrder.totalReleaseAmount.div(5)){
                        if (_thisTokenBalance >= _userOrder.totalReleaseAmount.div(5)){
                            _userOrder.releasedAmount = _userOrder.releasedAmount.add(_userOrder.totalReleaseAmount.div(5));
                            TransferHelper.safeTransfer(address(_snowToken), account, _userOrder.totalReleaseAmount.div(5));
                            emit SnowTokenReleased(account, _bigAddress, _userOrder.totalReleaseAmount.div(5), _curSmallAch, _ttAch);
                            // _userOrder.lastReleaseTime = block.timestamp;
                            _userOrder.lastCalcTotalAch = _ttAch;
                            _userOrder.lastCalcBigAddress = _bigAddress;
                            userOrder[account] = _userOrder;                            
                        }
                    }else{
                        if (_thisTokenBalance >= _restReleaseAmount){
                            _userOrder.releasedAmount = _userOrder.releasedAmount.add(_restReleaseAmount);
                            TransferHelper.safeTransfer(address(_snowToken), account, _restReleaseAmount);
                            emit SnowTokenReleased(account, _bigAddress, _restReleaseAmount, _curSmallAch, _ttAch);
                            // _userOrder.lastReleaseTime = block.timestamp;
                            _userOrder.lastCalcTotalAch = _ttAch;
                            _userOrder.lastCalcBigAddress = _bigAddress;
                            userOrder[account] = _userOrder;
                        }
                    }                    
                }
            }
        }
    }

    function staticDayReleaseSnowToken() nonReentrant external returns(bool){        
        bool isok = false;
        address from = _msgSender();

        require(from != address(0) && address(_snowToken) !=address(0), "Snowtoken error or not seted");
        require(!_isBlocked[from], "address blocked");

        OrderInfo memory _userOrder = userOrder[from];
        if (_userOrder.totalReleaseAmount>0) {
            uint256 _thisTokenBalance = _snowToken.balanceOf(address(this));
            uint256 _restReleaseAmount = _userOrder.totalReleaseAmount.sub(_userOrder.releasedAmount);
            require(_restReleaseAmount>0, "all tokens released");

            if (block.timestamp.sub(_userOrder.lastReleaseTime)>= 1 days){
                if (_restReleaseAmount>=_userOrder.totalReleaseAmount.div(1000)){
                     require(_thisTokenBalance >= _userOrder.totalReleaseAmount.div(1000),"this contract insufficient funds");
                    _userOrder.releasedAmount = _userOrder.releasedAmount.add(_userOrder.totalReleaseAmount.div(1000));
                    _userOrder.lastReleaseTime = block.timestamp;
                    TransferHelper.safeTransfer(address(_snowToken), from, _userOrder.totalReleaseAmount.div(1000));
                    emit SnowTokenReleased(from, _userOrder.lastCalcBigAddress, _userOrder.totalReleaseAmount.div(1000), 
                        _userOrder.lastCalcSmallAch, _userOrder.lastCalcTotalAch);
                    userOrder[from] = _userOrder;
                    isok = true;
                }else{
                     require(_thisTokenBalance >= _restReleaseAmount,"this contract insufficient funds");
                    _userOrder.releasedAmount = _userOrder.releasedAmount.add(_restReleaseAmount);
                    _userOrder.lastReleaseTime = block.timestamp;
                    TransferHelper.safeTransfer(address(_snowToken), from, _restReleaseAmount);
                    emit SnowTokenReleased(from, _userOrder.lastCalcBigAddress, _restReleaseAmount, 
                        _userOrder.lastCalcSmallAch, _userOrder.lastCalcTotalAch);
                    userOrder[from] = _userOrder;
                    isok = true;
                }
            }
        }

        return isok;
    }
    
    function payForIDO(address invitaddress, uint256 amount) nonReentrant external {
        address from = _msgSender();
        require(!_isBlocked[invitaddress] && !_isBlocked[from], "your address or inviter address has blocked");
        require(from != address(0) && !isContract(from), "Error from address");
        require(invitaddress != address(0) && !isContract(invitaddress), "Error inviter address");
        require(amount==idoAmount1||amount==idoAmount2||amount==idoAmount3,"Error IDO amount");
        require(inviterMe[from] == address(0), "address is not newer");
        require(meInvited[from].length==0, "Address invited users");  
        require(address(paytoken) != address(0), "Pay token is not set");
        require(initIDOPrice>0, "init IDO price not set");
        require(!idoFinished, "IDO has finished");
        uint256 ttRelAmount = amount.mul(initIDOPrice);
        totalIDOAmount = totalIDOAmount.sub(ttRelAmount);
        require(totalIDOAmount>=0, "IDO has finished");

        address _newinviterups = inviterMe[invitaddress];
        if (idoUsers.length>0){
            require(_newinviterups!=address(0),"inviter invaild");
        }

        while (_newinviterups!=address(0)) {
            require(_newinviterups != from && !_isBlocked[_newinviterups], "you are higher-ups of newinviter or have blocked ups");
            _newinviterups = inviterMe[_newinviterups];
        }

        if (idoUsers.length>0){
            for (uint i=0;i<idoUsers.length;i++){
                require(idoUsers[i] != from, "Address has joined IDO");
            }
        }
        idoUsers.push(from); 
        
        if (meInvited[invitaddress].length>0){
            for (uint j=0;j<meInvited[invitaddress].length;j++){
                require(meInvited[invitaddress][j] != from, "you are already be invited");
            }
        }

        inviterMe[from] = invitaddress; 
        meInvited[invitaddress].push(from); 

        uint256 minAmount = IERC20(paytoken).allowance(from, address(this));
        require(minAmount >= amount, "Approved allowance not enough");

        TransferHelper.safeTransferFrom(address(paytoken), from, address(this), amount);
        
        TransferHelper.safeTransfer(address(paytoken), invitaddress, amount.div(10)); 
        OrderInfo memory invitaddrOrder = userOrder[invitaddress];
        uint256 _invitRewards = invitaddrOrder.invitRewards.add(amount.div(10));
        invitaddrOrder.invitRewards = _invitRewards;
        userOrder[invitaddress] = invitaddrOrder;

        uint256 myinvitrewards = userOrder[from].invitRewards;
        OrderInfo memory newOrder = OrderInfo({
            payAmount: amount,
            idoTime: block.timestamp,
            totalReleaseAmount: ttRelAmount,
            releasedAmount: 0,
            lastReleaseTime: 0,
            realtimeAch: 0,
            myAch: 0,
            invitRewards: myinvitrewards,
            lastCalcTotalAch: 0,
            lastCalcSmallAch: 0,
            lastCalcBigAddress: address(0)
        });

        userOrder[from] = newOrder;
        emit IDOJoined(from,invitaddress, amount, ttRelAmount);
    }
	
//================================================================================
    constructor(uint256 _idoamount1,uint256 _idoamount2,uint256 _idoamount3,
            uint256 _initidoprice, uint256 _totalidoamount, IERC20 _paytoken)  {
        _owner = msg.sender;
        _destroyAddress = address(0x000000000000000000000000000000000000dEaD);
        idoAmount1 = _idoamount1;
        idoAmount2 = _idoamount2;
        idoAmount3 = _idoamount3;
        initIDOPrice = _initidoprice;
        totalIDOAmount = _totalidoamount;
        paytoken = _paytoken;

    }
    
}
