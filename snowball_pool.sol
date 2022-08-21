
pragma solidity ^0.8.6;

import "./libs/ReentrancyGuard.sol";
import "./libs/Ownable.sol";
import "./libs/SafeMath.sol";
import "./libs/SafeERC20.sol";
import "./libs/IERC20.sol";
import "./libs/TransferHelp.sol";

import "./Snowball.sol";

// SPDX-License-Identifier: Unlicensed

interface ISnowBall {
    function getRepayRate() external view returns (uint256);
}

contract SNOWBPOOL is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 _snowToken;

    address public _destroyAddress;

    address[] public repayList;
    struct ReturnRec {
		uint256 returnAmount; 
		uint256 returnValue;
        uint256 returnTime;
    }

    struct RepayOrder {
        uint256 payedOrderId;
		uint256 payedAmount;
		uint256 payedValue;
        uint256 payTime;
        uint256 restReleaseValue;
        bool orderFinished;
    }

    struct FomoPayoutRecord {
        uint256 payoutTime;
        uint256 payoutTotalAmount;
        uint256 payoutTotalValue;
		address[] receiveAddressList;
    }

    mapping(uint256=>ReturnRec[]) public returnList;
    mapping(address => RepayOrder[]) public repayOrder;
    uint256 public repayFront;
    uint256 public repayRear;
    uint256 public repayListLength;
    
    uint256 public payedTotalAmount;
    uint256 public payedTotalValue;
    uint256 public incomeTotalAmount;
    uint256 public incomeTotalValue;
    uint256 public repayTotalValue;
    uint256 public repayTotalAmount;
    
    uint256 public fomoIncomeTotalAmount;
    uint256 public fomoIncomeTotalValue;
    uint256 public fomoPayoutTotalAmount;
    uint256 public fomoPayoutTotalValue;
    FomoPayoutRecord[]  fomoPayoutList;

    uint256 lastRepayOrderTime;

    event NewRepayOrder(address indexed user,uint256 orderid, uint256 amount, uint256 value);
    event NewReturnOrder(address indexed user, uint256 orderid, uint256 amount, uint256 value);
    event NewFomoBurst(uint256 indexed orderid, bool istimeburst, uint256 amount, uint256 value, address[] receivelist);

    event NewFailEvent(uint failid);

    bool inburst;

    modifier lockTheBurst {
        inburst = true;
        _;
        inburst = false;
    }

    function isContract(address account) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }
    
    function isInRepayList(address account) public view returns(bool) {
        bool isok = false;
        if (repayListLength>0){
            uint256 myLen = repayOrder[account].length;
            if (myLen>0){
                bool orderfinish =  repayOrder[account][myLen-1].orderFinished;
                uint256 orderid = repayOrder[account][myLen-1].payedOrderId;
                if (!orderfinish && repayList[orderid]==account){
                    isok = true;
                }
            }
        }
        return isok;
    }
    
    function getRepayList() external view returns(address[] memory,uint256,uint256,uint256,uint256) {
        address from = _msgSender();
        
        uint256 _repayFront = repayFront;
        uint256 _repayRear = repayRear;
        uint256 _repayListLength = repayListLength;
        uint256 _myRank = 0;

        if (repayListLength>0){
            for (uint256 i = repayFront;i<=repayRear;i++){
                if (repayList[i]==from){
                    _myRank = i;
                }
            }
        }

        return (repayList,_repayFront,_repayRear,_repayListLength,_myRank);
    }

    function newReturnOrder(uint256 _amount,uint256 _value) nonReentrant public returns(bool){
        address from = _msgSender();
        bool isok;
        isok = _newReturnOrder(from, _amount, _value);
        return isok;
    }
    
    function _newReturnOrder(address from,uint256 _amount,uint256 _value) internal returns(bool){
        require(from == address(_snowToken) || from == address(this), "only invoked by sonwtoken contract");
        
        if (_amount == 0 || _value == 0){
            emit NewFailEvent(1);
            return false;
        } 

        bool isok = false;
        if (repayListLength==0){return isok;}
        
        address curReturnAddress;
        uint256 usrLastOrderIdx;
        uint256 currestValue;
        bool isfinished;
        uint256 _restvalue = _value;
        uint256 _restamount = _amount;
        uint256 _curamount;
        uint256 _curprice;
        if (_amount>=_value){
            _curprice = _amount.div(_value);
        }else{
            _curprice = _value.div(_amount);
        }

        while(repayListLength>0){
            curReturnAddress = repayList[repayFront];
            require(repayOrder[curReturnAddress].length>0,"internal error");
            usrLastOrderIdx = repayOrder[curReturnAddress].length-1;
            // RepayOrder memory curRepayOrder = repayOrder[curReturnAddress][usrLastOrderIdx];
            currestValue = repayOrder[curReturnAddress][usrLastOrderIdx].restReleaseValue;
            isfinished = repayOrder[curReturnAddress][usrLastOrderIdx].orderFinished;
            require(repayOrder[curReturnAddress][usrLastOrderIdx].payedOrderId==repayFront, "internal error");
            require(!isfinished && currestValue>0,"internal error");

            isok = true;
            if (currestValue>_restvalue){
                repayOrder[curReturnAddress][usrLastOrderIdx].restReleaseValue = currestValue.sub(_restvalue);
                ReturnRec memory newreturnrec = ReturnRec({
                    returnAmount: _restamount,
                    returnValue: _restvalue,
                    returnTime: block.timestamp
                });
                returnList[repayFront].push(newreturnrec);
                TransferHelper.safeTransfer(address(_snowToken), curReturnAddress, _restamount);
                emit NewReturnOrder(curReturnAddress, repayFront, _restamount, _restvalue);

                repayTotalAmount = repayTotalAmount.add(_restamount);
                _restvalue = 0;
                _restamount = 0;
                break;
            }else{
                _restvalue = _restvalue.sub(currestValue);
                
                if (_amount>=_value){
                    _curamount = currestValue.mul(_curprice);
                }else{
                    _curamount = currestValue.div(_curprice);
                }
                _restamount = _restamount.sub(_curamount);

                repayOrder[curReturnAddress][usrLastOrderIdx].restReleaseValue = 0;
                repayOrder[curReturnAddress][usrLastOrderIdx].orderFinished = true;

                ReturnRec memory newreturnrec = ReturnRec({
                    returnAmount: _curamount,
                    returnValue: currestValue,
                    returnTime: block.timestamp
                });
                returnList[repayFront].push(newreturnrec);
                if (repayFront<repayRear){
                    repayFront = repayFront.add(1);
                }
                
                repayListLength = repayListLength.sub(1);

                TransferHelper.safeTransfer(address(_snowToken), curReturnAddress, _curamount);
                emit NewReturnOrder(curReturnAddress, repayFront, _curamount, currestValue);

                repayTotalAmount = repayTotalAmount.add(_curamount);

                if (_restvalue==0){
                    break;
                }
            }
        }
        
        repayTotalValue = repayTotalValue.add(_value.sub(_restvalue));

        isok = true;
        return isok;
    }
    
    
    function newRepayOrder(address _account,uint256 _amount,uint256 _value) nonReentrant external returns(bool){
        address from = _msgSender();
        require(from == address(_snowToken) && _value>0, "only invoked by sonwtoken contract");
        bool isok = false;
        require(_value>=100*10**18 && _value<=500*10**18, "throw in value error");
        bool inlist = false;
        
        if (repayListLength>0){
            for (uint256 i=repayFront;i<repayList.length;i++){
                if (repayList[i] == _account) {
                    inlist = true;
                    break;
                }
            }
            require(!inlist, "should wait for your previous order finished");
        }

        uint256 thislastorderidx = repayOrder[_account].length;
        if (thislastorderidx>0){
            thislastorderidx=thislastorderidx-1;
            
            require(repayOrder[_account][thislastorderidx].orderFinished,"interal error");
        }

        if (repayList[repayFront] == _destroyAddress){
            require(repayRear==0, "internal error");
            repayList.push(_account);
            repayFront = repayFront.add(1);
            repayRear = repayRear.add(1);
            repayListLength = 1;

            RepayOrder memory newOrder = RepayOrder({
                payedOrderId: repayRear, 
                payedAmount:  _amount,
                payedValue:  _value,
                payTime:    block.timestamp,
                restReleaseValue:   _value.mul(15).div(10), 
                orderFinished: false
            });
            repayOrder[_account].push(newOrder);
            
            payedTotalAmount = payedTotalAmount.add(_amount);
            payedTotalValue = payedTotalValue.add(_value);
            emit NewRepayOrder(_account, repayRear, _amount, _value);
            
        }else{
           if (repayFront == repayRear){
                if (repayListLength==1){
                    address lastaddress = repayList[repayRear];
                    repayList.push(_account);
                    repayRear = repayRear.add(1);
                    require(repayRear==(repayList.length-1), "internal error");

                    RepayOrder memory newOrder = RepayOrder({
                        payedOrderId: repayRear, 
                        payedAmount:  _amount,
                        payedValue:  _value,
                        payTime:    block.timestamp,
                        restReleaseValue:   _value.mul(15).div(10), 
                        orderFinished: false
                    });
                    repayOrder[_account].push(newOrder); 
                    require(repayOrder[lastaddress].length>0, "internal error");

                    payedTotalAmount = payedTotalAmount.add(_amount);
                    payedTotalValue = payedTotalValue.add(_value);
                    repayListLength = repayListLength.add(1); 
                    emit NewRepayOrder(_account, repayRear, _amount, _value);

                }else{
                    require(repayListLength==0,"internal error");
                    repayList.push(_account);
                    repayFront = repayFront.add(1);
                    repayRear = repayRear.add(1);
                    repayListLength = 1;

                    RepayOrder memory newOrder = RepayOrder({
                        payedOrderId: repayRear, 
                        payedAmount:  _amount,
                        payedValue:  _value,
                        payTime:    block.timestamp,
                        restReleaseValue:   _value.mul(15).div(10), 
                        orderFinished: false
                    });
                    repayOrder[_account].push(newOrder);

                    payedTotalAmount = payedTotalAmount.add(_amount);
                    payedTotalValue = payedTotalValue.add(_value);
                    emit NewRepayOrder(_account, repayRear, _amount, _value);
                }
           }else{
                require(repayRear>repayFront, "internal error");
                address lastaddress = repayList[repayRear];
                repayList.push(_account);
                repayRear = repayRear.add(1);
                require(repayRear==(repayList.length-1),"internal error");

                RepayOrder memory newOrder = RepayOrder({
                    payedOrderId: repayRear, 
                    payedAmount:  _amount,
                    payedValue:  _value,
                    payTime:    block.timestamp,
                    restReleaseValue:   _value.mul(15).div(10), 
                    orderFinished: false
                });
                
                repayOrder[_account].push(newOrder); 

                require(repayOrder[lastaddress].length>0, "internal error");

                payedTotalAmount = payedTotalAmount.add(_amount);
                payedTotalValue = payedTotalValue.add(_value);
                repayListLength = repayListLength.add(1);
                emit NewRepayOrder(_account, repayRear, _amount, _value);
           }
        }
        
        lastRepayOrderTime = block.timestamp;
        isok = true;
        return isok;
    }
    
    function putinFomoPool(uint256 _amount,uint256 _value) nonReentrant external returns(bool){
        address from = _msgSender();
        require(from == address(_snowToken) && _value>0, "only invoked by sonwtoken contract");
        bool isok = false;
        
        if (_amount>0 && _value>0){
            fomoIncomeTotalAmount = fomoIncomeTotalAmount.add(_amount);
            fomoIncomeTotalValue = fomoIncomeTotalValue.add(_value);
            
            if (fomoIncomeTotalValue.sub(fomoPayoutTotalValue)>=3000*10**18){
                _burstFomoPool(address(this), false);
            }
            isok = true;
        }
        
        return isok;
    }

    function putinRepayPool(uint256 _amount,uint256 _value) nonReentrant external returns(bool){
        address from = _msgSender();
        require(from == address(_snowToken) && _value>0, "only invoked by sonwtoken contract");
        bool isok = false;
        if (_amount>0 && _value>0){
            incomeTotalAmount = incomeTotalAmount.add(_amount);
            incomeTotalValue = incomeTotalValue.add(_value);
            isok = true;
        }
        
        return isok;
    }

    function burstFomoPool(bool _istimeburst) nonReentrant external returns(bool) {
        address from = _msgSender();
        bool isok = false;

        isok = _burstFomoPool(from, _istimeburst);

        return isok;
    }

    function _taketransfer(address token,address to,uint256 amount) lockTheBurst internal {
        TransferHelper.safeTransfer(token, to, amount);   
    }

    function _burstFomoPool(address _from,bool _istimeburst) internal returns(bool){
        if (inburst){return false;}
        require(_from == address(_snowToken) || _from == address(this), "only invoked by sonwtoken contract");
        bool isok = false;
        
        if (_istimeburst){
            //timeout burst
            if (repayList[repayRear] != _destroyAddress && repayListLength>0){
                address[] memory receivelist = new address[](1);
                uint256 burstAmount = fomoIncomeTotalAmount.sub(fomoPayoutTotalAmount);
                uint256 burstValue = fomoIncomeTotalValue.sub(fomoPayoutTotalValue);
                if (burstAmount > _snowToken.balanceOf(address(this))){
                    emit NewFailEvent(2);
                    return false;
                }
                receivelist[0] = repayList[repayRear];
                FomoPayoutRecord memory newfomopayoutrec = FomoPayoutRecord({
                    payoutTime: block.timestamp,
                    payoutTotalAmount: burstAmount,
                    payoutTotalValue: burstValue,
                    receiveAddressList: receivelist
                });

                lastRepayOrderTime = 0;
                fomoPayoutList.push(newfomopayoutrec);

                _taketransfer(address(_snowToken),repayList[repayRear],burstAmount);
                
                fomoPayoutTotalAmount = fomoPayoutTotalAmount.add(burstAmount);
                fomoPayoutTotalValue = fomoPayoutTotalValue.add(burstValue);

                emit NewFomoBurst(fomoPayoutList.length-1, _istimeburst, burstAmount, burstValue, receivelist);
                isok = true;
                
            }
        }else{
            //value burst
            if (repayList[repayRear] != _destroyAddress && repayListLength>0){
                uint256 payoutlistlength;
                if (repayListLength<10){
                    payoutlistlength = repayListLength;
                }else{
                    payoutlistlength = 10;
                }

                address[] memory receivelist = new address[](payoutlistlength);
                uint256 burstAmount = (fomoIncomeTotalAmount.sub(fomoPayoutTotalAmount)).div(2);
                uint256 burstValue = (fomoIncomeTotalValue.sub(fomoPayoutTotalValue)).div(2);
                
                if (burstAmount > _snowToken.balanceOf(address(this))){
                    emit NewFailEvent(2);
                    return false;
                }
                
                for (uint256 i=0;i<payoutlistlength-1;i++){
                    receivelist[i] = repayList[repayRear-i];
                    _taketransfer(address(_snowToken),repayList[repayRear-i],burstAmount.div(payoutlistlength));
                }
                
                FomoPayoutRecord memory newfomopayoutrec = FomoPayoutRecord({
                    payoutTime: block.timestamp,
                    payoutTotalAmount: burstAmount,
                    payoutTotalValue: burstValue,
                    receiveAddressList: receivelist
                });

                fomoPayoutList.push(newfomopayoutrec);
                fomoPayoutTotalAmount = fomoPayoutTotalAmount.add(burstAmount);
                fomoPayoutTotalValue = fomoPayoutTotalValue.add(burstValue);
                
                emit NewFomoBurst(fomoPayoutList.length-1, _istimeburst, burstAmount, burstValue, receivelist);
                isok = true;
            }
        }
        return isok;
    }

    function setSnowToken(IERC20 _snowtoken) onlyOwner external {
        require(address(_snowtoken) != address(0) && isContract(address(_snowtoken)), "Error SnowToken address");
        _snowToken = _snowtoken;
    }
    
    function getRepayFrontAddress() external view returns(address) {
        if (repayListLength>0){
            return repayList[repayFront];
        }else{
            return _destroyAddress;
        }
    }
    
    function getRepayPoolAmountValue() external view returns(uint256 amount,uint256 value) {
        require(address(_snowToken)!=address(0),"snow token address not set");
        uint256 repayrate = ISnowBall(address(_snowToken)).getRepayRate();
        amount = payedTotalAmount.mul(repayrate).div(1000);
        value  = payedTotalValue.mul(repayrate).div(1000);
        amount = amount.add(incomeTotalAmount);
        value = value.add(incomeTotalValue);
        return (amount,value);
    }

    function getFomoPoolAmountValue()  external view returns(uint256 amount,uint256 value) {
        amount = fomoIncomeTotalAmount.sub(fomoPayoutTotalAmount);
        value = fomoIncomeTotalValue.sub(fomoPayoutTotalValue);

        return (amount,value);
    }

    function getFomoPayoutRecList() external view returns(FomoPayoutRecord[] memory) {
        FomoPayoutRecord[] memory b = fomoPayoutList;

        return b;
    }

    function getLastRepayOrderTime() external view returns(uint256) {
        return lastRepayOrderTime;
    }

    function getMyRepayOrder() external view returns(RepayOrder[] memory) {
        address from = _msgSender();
        RepayOrder[] memory b = repayOrder[from];

        return b;
    }

    function getUsrRepayOrder(address account) external view returns(RepayOrder[] memory) {
        address from = account;
        RepayOrder[] memory b = repayOrder[from];

        return b;
    }

    function getReturnRec(uint256 orderid) external view returns(ReturnRec[] memory) {
        ReturnRec[] memory b = returnList[orderid];

        return b;
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
//================================================================================
    constructor(IERC20 _snowtoken)  {
        _destroyAddress = address(0x000000000000000000000000000000000000dEaD);
        repayList.push(_destroyAddress);
        _snowToken = _snowtoken;

        repayFront = 0;
        repayRear = 0;
        repayListLength = 0;
    
        payedTotalAmount = 0;
        payedTotalValue = 0;
        incomeTotalAmount = 0;
        incomeTotalValue = 0;
        repayTotalValue = 0;
        repayTotalAmount = 0;

        fomoIncomeTotalAmount = 0;
        fomoIncomeTotalValue = 0;
        fomoPayoutTotalAmount = 0;
        fomoPayoutTotalValue = 0;

        lastRepayOrderTime = 0;


    }
    
}
